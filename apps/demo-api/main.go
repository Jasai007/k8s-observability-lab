// demo-api is a tiny, heavily-commented "order service" used by every lab in
// this repository. It is intentionally small so you can read the whole file in
// one sitting and understand exactly where each observability signal comes from.
//
// It emits all three signals:
//
//	Metrics -> GET /metrics     (Prometheus text format via prometheus/client_golang)
//	Logs    -> stdout           (structured JSON via log/slog, every line carries trace_id)
//	Traces  -> OTLP (optional)  (OpenTelemetry; activates only when
//	                             OTEL_EXPORTER_OTLP_ENDPOINT is set)
//
// Endpoints:
//
//	GET /health       -> liveness probe (excluded from metrics, keeps dashboards clean)
//	GET /metrics      -> Prometheus scrape target (also excluded from metrics)
//	GET /api/orders   -> creates an order; calls the payment service if DEPENDENCY_URL is set
//	GET /api/payment  -> "downstream" payment service (used when this binary runs as demo-payment)
//
// Fault injection (used by the incident-response lab):
//
//	?fail=1           -> handler returns HTTP 500
//	?slow=1           -> handler sleeps ~2s before responding
package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"log/slog"
	"math/rand"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"syscall"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/codes"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
	"go.opentelemetry.io/otel/propagation"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	"go.opentelemetry.io/otel/trace"
)

// ---------------------------------------------------------------------------
// 1. Metric definitions
//
// Naming convention followed here (adopt it in your own services):
//
//	http_requests_total            counter   -> "how many requests, by status?"
//	http_request_duration_seconds  histogram -> "how slow are requests, per route?"
//	http_requests_in_flight        gauge     -> "how many requests right now?"
//	orders_total                   counter   -> business metric, not HTTP-specific
//
// Label (a.k.a. dimension) rule of thumb: only LOW-CARDINALITY, bounded values.
// "route" is the route *template* (/api/orders), never a raw URL with IDs.
// Never label by user_id, request_id or anything unbounded — that is the #1
// cause of Prometheus memory blow-ups in production (see module 11).
// ---------------------------------------------------------------------------
var (
	httpRequestsTotal = promauto.NewCounterVec(
		prometheus.CounterOpts{
			Name: "http_requests_total",
			Help: "Total HTTP requests handled, partitioned by outcome.",
		},
		[]string{"service", "method", "route", "status"},
	)

	httpRequestDuration = promauto.NewHistogramVec(
		prometheus.HistogramOpts{
			Name:    "http_request_duration_seconds",
			Help:    "Latency of HTTP requests. Buckets suit a lab: 5ms..5s.",
			Buckets: []float64{.005, .01, .025, .05, .1, .25, .5, 1, 2.5, 5},
		},
		[]string{"service", "method", "route"},
	)

	httpInFlight = promauto.NewGauge(
		prometheus.GaugeOpts{
			Name: "http_requests_in_flight",
			Help: "Number of HTTP requests currently being processed.",
		},
	)

	// A business (domain) metric. Real services should expose a handful of
	// these: they answer "is the *business* healthy?", not just "is the
	// process running?".
	ordersTotal = promauto.NewCounterVec(
		prometheus.CounterOpts{
			Name: "orders_total",
			Help: "Orders processed by outcome (success|failed).",
		},
		[]string{"service", "status"},
	)
)

// ---------------------------------------------------------------------------
// 2. Configuration (flags + environment variables)
//
// Environment variables are the standard way to configure containers:
//
//	--service                    logical service name (order|payment)
//	--listen                     port to listen on
//	DEPENDENCY_URL               if set, /api/orders calls this URL, which
//	                             enables real distributed tracing across pods
//	OTEL_EXPORTER_OTLP_ENDPOINT  if set (e.g. "otel-collector:4317") traces are
//	                             exported; if empty, tracing is a cheap no-op
//
// ---------------------------------------------------------------------------
type config struct {
	service       string
	listenAddr    string
	dependencyURL string
	otlpEndpoint  string
}

func loadConfig() config {
	var c config
	flag.StringVar(&c.service, "service", "order", "logical service name (order|payment)")
	flag.StringVar(&c.listenAddr, "listen", ":8080", "address to listen on")
	flag.Parse()

	c.dependencyURL = os.Getenv("DEPENDENCY_URL")
	c.otlpEndpoint = os.Getenv("OTEL_EXPORTER_OTLP_ENDPOINT")
	return c
}

// ---------------------------------------------------------------------------
// 3. Structured logging
//
// JSON lines are what log collectors (Fluent Bit -> Elasticsearch) expect.
// Every line carries the trace_id so you can jump from a log line straight to
// the matching trace — this is the core skill of signal correlation (module 09).
// ---------------------------------------------------------------------------
func newLogger(service string) *slog.Logger {
	// Note: NewJSONHandler returns *slog.JSONHandler; assigning to the
	// slog.Handler interface is what gives us .WithAttrs(...).
	var handler slog.Handler = slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelInfo})
	handler = handler.WithAttrs([]slog.Attr{slog.String("service", service)})
	return slog.New(handler)
}

// traceID returns the current trace id as a string ("" when tracing is off).
func traceID(ctx context.Context) string {
	if span := trace.SpanFromContext(ctx); span.SpanContext().IsValid() {
		return span.SpanContext().TraceID().String()
	}
	return ""
}

// ---------------------------------------------------------------------------
// 4. OpenTelemetry tracing (optional by design)
//
// Tracing activates ONLY when OTEL_EXPORTER_OTLP_ENDPOINT is set, so the same
// image runs unchanged in every module: modules 01-06 never pay the cost of
// tracing, module 07 switches it on via the Deployment env var.
//
// Inside the cluster the variable points at the OTel Collector ("otel-collector:4317",
// gRPC is the standard OTLP transport).
// ---------------------------------------------------------------------------
func startTracing(ctx context.Context, cfg config, log *slog.Logger) func(context.Context) error {
	if cfg.otlpEndpoint == "" {
		log.Info("tracing disabled: OTEL_EXPORTER_OTLP_ENDPOINT not set")
		return func(context.Context) error { return nil }
	}

	// WithInsecure = plaintext gRPC, normal inside a lab cluster.
	exporter, err := otlptracegrpc.New(ctx,
		otlptracegrpc.WithEndpoint(cfg.otlpEndpoint),
		otlptracegrpc.WithInsecure(),
	)
	if err != nil {
		log.Error("cannot create OTLP exporter, tracing disabled", "error", err)
		return func(context.Context) error { return nil }
	}

	tp := sdktrace.NewTracerProvider(
		sdktrace.WithBatcher(exporter), // batch spans instead of one-per-RPC
		sdktrace.WithResource(resource.NewWithAttributes(
			"", // schema URL; empty is fine for these ad-hoc attributes
			attribute.String("service.name", cfg.service), // shown as the service name in Jaeger
			attribute.String("service.version", "0.1.0"),
		)),
	)

	otel.SetTracerProvider(tp)
	// Propagation = how trace context travels between services (W3C traceparent header).
	otel.SetTextMapPropagator(propagation.TraceContext{})
	log.Info("tracing enabled", "otlp_endpoint", cfg.otlpEndpoint)

	return tp.Shutdown
}

// ---------------------------------------------------------------------------
// 5. HTTP middleware: metrics + tracing + access logging in ONE place
//
// This is exactly where you should add all three signals in a real service —
// instrument once at the edge of the app, and every handler gets it for free.
// ---------------------------------------------------------------------------

// statusRecorder captures the response status code so metrics can be labeled
// with it (a thin wrapper around http.ResponseWriter).
type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (r *statusRecorder) WriteHeader(code int) {
	r.status = code
	r.ResponseWriter.WriteHeader(code)
}

// normalizeRoute turns a concrete path into a bounded label value so that
// unknown or ID-bearing paths can never explode metric cardinality.
func normalizeRoute(path string) string {
	switch path {
	case "/health", "/api/orders", "/api/payment":
		return path
	default:
		return "other"
	}
}

func instrument(cfg config, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// Skip the boring endpoints so dashboards stay readable.
		if r.URL.Path == "/health" || r.URL.Path == "/metrics" {
			next.ServeHTTP(w, r)
			return
		}

		start := time.Now()
		// Extract incoming trace context (traceparent header) if a caller sent one.
		ctx := otel.GetTextMapPropagator().Extract(r.Context(), propagation.HeaderCarrier(r.Header))

		// Server span: this request becomes one span in a trace.
		ctx, span := otel.Tracer("demo-api/http").Start(ctx,
			"HTTP "+r.Method+" "+normalizeRoute(r.URL.Path),
			trace.WithSpanKind(trace.SpanKindServer))
		defer span.End()

		rec := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
		httpInFlight.Inc()
		defer httpInFlight.Dec()

		next.ServeHTTP(rec, r.WithContext(ctx)) // ctx flows into logs and child spans

		route := normalizeRoute(r.URL.Path)
		status := strconv.Itoa(rec.status)
		elapsed := time.Since(start)

		// --- metrics ---
		httpRequestsTotal.WithLabelValues(cfg.service, r.Method, route, status).Inc()
		httpRequestDuration.WithLabelValues(cfg.service, r.Method, route).Observe(elapsed.Seconds())

		// --- trace status: mark server errors so they stand out in Jaeger ---
		if rec.status >= 500 {
			span.SetStatus(codes.Error, fmt.Sprintf("HTTP %d", rec.status))
			span.RecordError(errors.New("server error"))
		}

		// --- structured access log (trace_id is attached automatically) ---
		level := slog.LevelInfo
		if rec.status >= 500 {
			level = slog.LevelError
		}
		slog.Log(ctx, level, "http request",
			"method", r.Method,
			"path", r.URL.Path,
			"route", route,
			"status", rec.status,
			"duration_ms", elapsed.Milliseconds(),
			"trace_id", traceID(ctx),
		)
	})
}

// ---------------------------------------------------------------------------
// 6. Handlers
// ---------------------------------------------------------------------------

// writeJSON keeps the handlers readable.
func writeJSON(w http.ResponseWriter, status int, payload any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(payload)
}

// newMux builds all routes for whichever role this process plays.
func newMux(cfg config, log *slog.Logger) http.Handler {
	mux := http.NewServeMux()

	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, map[string]string{"status": "ok", "service": cfg.service})
	})

	// /api/orders — the entry point of our little business flow.
	mux.HandleFunc("/api/orders", func(w http.ResponseWriter, r *http.Request) {
		ctx := r.Context()
		start := time.Now()

		// Fault injection used by the incident lab (?fail=1 / ?slow=1).
		if r.URL.Query().Get("slow") == "1" {
			time.Sleep(2 * time.Second) // -> latency alert
		}
		if r.URL.Query().Get("fail") == "1" {
			ordersTotal.WithLabelValues(cfg.service, "failed").Inc()
			log.ErrorContext(ctx, "order failed (injected fault)",
				"trace_id", traceID(ctx), "path", r.URL.Path)
			writeJSON(w, http.StatusInternalServerError,
				map[string]string{"error": "payment gateway rejected the order"})
			return
		}

		// Internal child span: shows *work inside* one request. Spans nest
		// like a call tree in the trace UI.
		ctx, span := otel.Tracer("demo-api/orders").Start(ctx, "orders.validate")
		time.Sleep(time.Duration(20+rand.Intn(60)) * time.Millisecond)
		span.End()

		order := map[string]any{
			"order_id":    fmt.Sprintf("ord-%d", rand.Intn(1_000_000)),
			"service":     cfg.service,
			"status":      "confirmed",
			"duration_ms": time.Since(start).Milliseconds(),
		}

		// Optional cross-service call. When DEPENDENCY_URL is set, the trace
		// continues into the payment pod — that is what makes tracing
		// *distributed*: one trace ID stitches both services together.
		if cfg.dependencyURL != "" {
			payment, err := callPayment(ctx, cfg.dependencyURL, log)
			if err != nil {
				ordersTotal.WithLabelValues(cfg.service, "failed").Inc()
				log.ErrorContext(ctx, "payment dependency failed",
					"dependency", cfg.dependencyURL, "error", err, "trace_id", traceID(ctx))
				writeJSON(w, http.StatusBadGateway,
					map[string]string{"error": "payment service unavailable", "detail": err.Error()})
				return
			}
			order["payment"] = payment
		}

		ordersTotal.WithLabelValues(cfg.service, "success").Inc()
		writeJSON(w, http.StatusOK, order)
	})

	// /api/payment — same binary, deployed as the "demo-payment" service.
	mux.HandleFunc("/api/payment", func(w http.ResponseWriter, r *http.Request) {
		ctx := r.Context()
		if r.URL.Query().Get("fail") == "1" {
			ordersTotal.WithLabelValues(cfg.service, "failed").Inc()
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "card declined"})
			return
		}
		// Child span = the actual work this service performs.
		_, span := otel.Tracer("demo-api/payment").Start(ctx, "payment.charge")
		time.Sleep(time.Duration(30+rand.Intn(70)) * time.Millisecond)
		span.End()

		writeJSON(w, http.StatusOK, map[string]any{"status": "charged", "service": cfg.service})
	})

	mux.Handle("/metrics", promhttp.Handler())
	return mux
}

// callPayment performs the downstream HTTP call and *injects* the current
// trace context into the headers, so the payment service continues the same
// trace instead of starting a new one (context propagation).
func callPayment(ctx context.Context, url string, log *slog.Logger) (string, error) {
	ctx, span := otel.Tracer("demo-api/client").Start(ctx, "GET "+url,
		trace.WithSpanKind(trace.SpanKindClient))
	defer span.End()

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		span.RecordError(err)
		return "", err
	}
	otel.GetTextMapPropagator().Inject(ctx, propagation.HeaderCarrier(req.Header)) // <- propagation

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		span.SetStatus(codes.Error, err.Error())
		span.RecordError(err)
		log.ErrorContext(ctx, "dependency call failed", "url", url, "error", err)
		return "", err
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 400 {
		err := fmt.Errorf("payment returned HTTP %d", resp.StatusCode)
		span.SetStatus(codes.Error, err.Error())
		span.RecordError(err)
		return "", err
	}
	return "charged", nil
}

// ---------------------------------------------------------------------------
// 7. main: wire everything together + graceful shutdown
// ---------------------------------------------------------------------------
func main() {
	cfg := loadConfig()

	// Logger first — everything else logs through it.
	log := newLogger(cfg.service).With("listen", cfg.listenAddr)
	slog.SetDefault(log)

	// ctx is cancelled on SIGINT/SIGTERM (Ctrl-C, pod termination).
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	// Tracing starts before any handler runs; shutdown flushes queued spans.
	shutdownTracer := startTracing(ctx, cfg, log)
	defer func() {
		c, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		if err := shutdownTracer(c); err != nil {
			log.Error("tracer shutdown error", "error", err)
		}
	}()

	mux := newMux(cfg, log)
	server := &http.Server{
		Addr:              cfg.listenAddr,
		Handler:           instrument(cfg, mux),
		ReadHeaderTimeout: 5 * time.Second,
	}

	// Run the HTTP server in the background...
	go func() {
		log.Info("demo-api listening",
			"dependency", cfg.dependencyURL,
			"tracing", cfg.otlpEndpoint != "")
		if err := server.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Error("server failed", "error", err)
			os.Exit(1)
		}
	}()

	// ...wait for a shutdown signal, then drain connections gracefully —
	// the same pattern you should use for any production service.
	<-ctx.Done()
	log.Info("shutting down")
	shCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	_ = server.Shutdown(shCtx)
}

package main

import (
	"fmt"
	"log"
	"os"

	"github.com/gin-gonic/gin"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	"github.com/trainwithshubham/skillpulse/database"
	"github.com/trainwithshubham/skillpulse/handlers"
)

var (
	httpRequestsTotal = prometheus.NewCounterVec(
		prometheus.CounterOpts{
			Name: "http_requests_total",
			Help: "Total number of HTTP requests",
		},
		[]string{"method", "endpoint", "status"},
	)
	httpRequestDuration = prometheus.NewHistogramVec(
		prometheus.HistogramOpts{
			Name:    "http_request_duration_seconds",
			Help:    "HTTP request duration in seconds",
			Buckets: prometheus.DefBuckets,
		},
		[]string{"method", "endpoint"},
	)
)

func init() {
	prometheus.MustRegister(httpRequestsTotal)
	prometheus.MustRegister(httpRequestDuration)
}

func prometheusMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		if c.Request.URL.Path == "/metrics" {
			c.Next()
			return
		}
		timer := prometheus.NewTimer(httpRequestDuration.WithLabelValues(
			c.Request.Method,
			c.FullPath(),
		))
		c.Next()
		timer.ObserveDuration()
		httpRequestsTotal.WithLabelValues(
			c.Request.Method,
			c.FullPath(),
			fmt.Sprintf("%d", c.Writer.Status()),
		).Inc()
	}
}

func main() {
	log.Printf("SkillPulse API starting up...")
	database.Connect()
	router := gin.Default()

	// Prometheus middleware
	router.Use(prometheusMiddleware())

	// Metrics endpoint
	router.GET("/metrics", gin.WrapH(promhttp.Handler()))

	// API routes
	api := router.Group("/api")
	{
		api.GET("/skills", handlers.GetSkills)
		api.POST("/skills", handlers.CreateSkill)
		api.GET("/skills/:id", handlers.GetSkill)
		api.DELETE("/skills/:id", handlers.DeleteSkill)
		api.POST("/skills/:id/log", handlers.CreateLog)
		api.GET("/dashboard", handlers.GetDashboard)
	}

	// Health check
	router.GET("/health", handlers.HealthCheck)

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	log.Printf("SkillPulse API running on port %s", port)
	if err := router.Run(":" + port); err != nil {
		log.Fatal(err)
	}
}

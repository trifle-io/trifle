#!/bin/bash

# Test Metrics API - Simple CURL examples
# Usage: ./test_metrics.sh YOUR_TOKEN_HERE

TOKEN=${1:-"your_token_here"}
BASE_URL="http://localhost:4000/api/metrics"

if [ "$TOKEN" = "your_token_here" ]; then
    echo "❌ Please provide your project token as the first argument:"
    echo "   ./test_metrics.sh YOUR_TOKEN_HERE"
    exit 1
fi

echo "🚀 Testing Trifle Metrics API with token: ${TOKEN:0:10}..."

# Simple page views metric
echo "📊 Submitting page views..."
curl -X POST "$BASE_URL" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "key": "page_views",
    "at": "'$(date -u -v-1H +%Y-%m-%dT%H:%M:%SZ)'",
    "values": {
      "total": 1250,
      "unique": 890,
      "pages": {
        "home": 650,
        "dashboard": 400,
        "profile": 200
      },
      "sources": {
        "direct": 500,
        "google": 450,
        "social": 300
      }
    }
  }' \
  -w "\nStatus: %{http_code}\n\n"

# API calls metric
echo "🔌 Submitting API calls..."
curl -X POST "$BASE_URL" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "key": "api_calls", 
    "at": "'$(date -u -v-30M +%Y-%m-%dT%H:%M:%SZ)'",
    "values": {
      "total": 3450,
      "endpoints": {
        "/api/users": 1200,
        "/api/projects": 850,
        "/api/metrics": 1100,
        "/api/tokens": 300
      },
      "status_codes": {
        "200": 3200,
        "400": 150,
        "401": 80,
        "500": 20
      }
    }
  }' \
  -w "\nStatus: %{http_code}\n\n"

# User signups metric
echo "👥 Submitting user signups..."
curl -X POST "$BASE_URL" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "key": "user_signups",
    "at": "'$(date -u -v-45M +%Y-%m-%dT%H:%M:%SZ)'",
    "values": {
      "count": 15,
      "sources": {
        "organic": 8,
        "referral": 4,
        "paid": 3
      },
      "conversion_rate": 3.2
    }
  }' \
  -w "\nStatus: %{http_code}\n\n"

# Performance metrics
echo "⚡ Submitting performance metrics..."  
curl -X POST "$BASE_URL" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "key": "performance",
    "at": "'$(date -u -v-15M +%Y-%m-%dT%H:%M:%SZ)'",
    "values": {
      "avg_response_time": 450,
      "requests": {
        "fast": 1200,
        "medium": 300,
        "slow": 50
      },
      "memory_usage": 65.5,
      "cpu_usage": 32.8
    }
  }' \
  -w "\nStatus: %{http_code}\n\n"

echo "✅ Test complete! Check your Trifle dashboard for the submitted metrics."
#!/bin/bash
# Quick Start Deployment Script
# This script sets up and starts the Bus Tracking backend

set -e

echo "================================"
echo "Bus Tracking Backend - Quick Start"
echo "================================"
echo ""

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo "✗ Docker is not installed. Please install Docker first."
    echo "  Visit: https://docs.docker.com/get-docker/"
    exit 1
fi

if ! command -v docker-compose &> /dev/null; then
    echo "✗ Docker Compose is not installed. Please install it."
    echo "  Visit: https://docs.docker.com/compose/install/"
    exit 1
fi

echo "✓ Docker and Docker Compose installed"
echo ""

# Check if .env file exists
if [ ! -f "bus_tracking_backend/.env" ]; then
    echo "Creating .env file from template..."
    cp bus_tracking_backend/.env.example bus_tracking_backend/.env
    echo "✓ .env file created"
    echo ""
    echo "⚠ Important: Edit bus_tracking_backend/.env with your Firebase credentials:"
    echo "  - FCM_SERVER_KEY"
    echo "  - FCM_PROJECT_ID"
    echo "  - FCM_SENDER_ID"
    echo "  - FIREBASE_CREDENTIALS_PATH"
    echo ""
    read -p "Press Enter after editing .env file..."
fi

# Check if serviceAccountKey.json exists
if [ ! -f "bus_tracking_backend/serviceAccountKey.json" ]; then
    echo ""
    echo "⚠ Firebase service account key not found!"
    echo "  Download from Firebase Console:"
    echo "  1. Go to Project Settings"
    echo "  2. Service Accounts tab"
    echo "  3. 'Generate new private key'"
    echo "  4. Save as: bus_tracking_backend/serviceAccountKey.json"
    echo ""
    read -p "Press Enter after downloading the service account key..."
fi

# Start Docker Compose
echo ""
echo "Starting Docker Compose services..."
echo "(This may take 1-2 minutes on first run)"
echo ""

docker-compose up --build

echo ""
echo "================================"
echo "Backend is now running!"
echo "================================"
echo ""
echo "Access points:"
echo "  API Documentation: http://localhost:8000/docs"
echo "  Health Check:      http://localhost:8000/health"
echo "  MinIO Console:      http://localhost:9001"
echo ""
echo "Test with:"
echo "  curl http://localhost:8000/health"
echo ""
echo "To stop:"
echo "  Ctrl+C then: docker-compose down"
echo ""

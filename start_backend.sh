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

# Load FIREBASE_KEY from firebase-key.json for Docker Compose pass-through
if [ -f "bus_tracking_backend/firebase-key.json" ]; then
    export FIREBASE_KEY="$(cat bus_tracking_backend/firebase-key.json)"
    echo "✓ FIREBASE_KEY loaded from firebase-key.json"
else
    echo "⚠ Firebase key file not found at bus_tracking_backend/firebase-key.json"
    echo "  Set the FIREBASE_KEY environment variable manually before continuing."
fi
echo ""

# Check if .env file exists
if [ ! -f "bus_tracking_backend/.env" ]; then
    echo "Creating .env file from template..."
    cp bus_tracking_backend/.env.example bus_tracking_backend/.env
    echo "✓ .env file created"
    echo ""
    echo "⚠ Important: Edit bus_tracking_backend/.env with your configuration:"
    echo "  - SECRET_KEY"
    echo "  - Database settings (DATABASE_URL)"
    echo "  - Or set FIREBASE_KEY directly in your shell environment"
    echo ""
    read -p "Press Enter after editing .env file..."
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

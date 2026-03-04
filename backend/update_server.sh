#!/bin/bash

echo "======================================"
echo "🚀 FASTAPI SERVER AUTO DEPLOY"
echo "======================================"

echo "📥 Pulling latest code from GitHub..."
git pull

echo "📦 Building Docker image..."
docker build -t fastapi-backend .

echo "🛑 Stopping old container..."
docker stop fastapi-container 2>/dev/null

echo "🧹 Removing old container..."
docker rm fastapi-container 2>/dev/null

echo "▶ Starting new container..."
docker run -d \
-p 8001:8000 \
--restart always \
-v ~/document_server/uploaded_files:/app/uploaded_files \
--name fastapi-container \
fastapi-backend

echo "🧽 Cleaning unused Docker images..."
docker image prune -f

echo "======================================"
echo "✅ DEPLOYMENT COMPLETE"
echo "======================================"

echo "🌐 API URL:"
echo "http://$(hostname -I | awk '{print $1}'):8001/docs"

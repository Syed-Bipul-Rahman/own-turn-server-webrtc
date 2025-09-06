# WebRTC Signaling Server Deployment Guide

## Deploy to Google Cloud Platform

Since you already have your TURN server running on GCP at `34.71.140.192:3478`, this guide will help you deploy the signaling server to the same cloud environment.

### Prerequisites

1. **Google Cloud Account** with billing enabled
2. **GCloud CLI** installed and authenticated
3. **Docker** (for Cloud Run deployment)
4. **Node.js** (for local testing)

### Deployment Options

Choose one of these deployment methods:

## Option 1: Google Cloud Run (Recommended)

Cloud Run is serverless, automatically scales, and is cost-effective.

### Step 1: Setup GCP Project

```bash
# Set your project ID (replace with your actual project ID)
export PROJECT_ID="your-project-id"
gcloud config set project $PROJECT_ID

# Enable required APIs
gcloud services enable run.googleapis.com
gcloud services enable cloudbuild.googleapis.com
gcloud services enable containerregistry.googleapis.com
```

### Step 2: Build and Deploy

```bash
# Build and deploy using Cloud Build
gcloud builds submit --config cloudbuild.yaml .

# Or manually build and deploy
docker build -t gcr.io/$PROJECT_ID/webrtc-signaling .
docker push gcr.io/$PROJECT_ID/webrtc-signaling

gcloud run deploy webrtc-signaling \
  --image gcr.io/$PROJECT_ID/webrtc-signaling \
  --platform managed \
  --region us-central1 \
  --allow-unauthenticated \
  --port 8080 \
  --memory 512Mi \
  --cpu 1 \
  --max-instances 10
```

### Step 3: Get Your Deployment URL

```bash
# Get the service URL
gcloud run services describe webrtc-signaling --region us-central1 --format 'value(status.url)'
```

Your signaling server will be available at: `https://webrtc-signaling-xxxxx-uc.a.run.app`

## Option 2: Google App Engine

App Engine provides automatic scaling and is easy to deploy.

### Step 1: Deploy to App Engine

```bash
# Deploy using app.yaml configuration
gcloud app deploy app.yaml

# Get the URL
gcloud app browse
```

Your signaling server will be available at: `https://your-project-id.uc.r.appspot.com`

## Option 3: Compute Engine VM

For more control, deploy on a VM instance.

### Step 1: Create VM Instance

```bash
# Create a small VM instance
gcloud compute instances create webrtc-signaling \
  --zone=us-central1-a \
  --machine-type=e2-micro \
  --image-family=ubuntu-2004-lts \
  --image-project=ubuntu-os-cloud \
  --tags=webrtc-signaling

# Create firewall rule
gcloud compute firewall-rules create allow-webrtc-signaling \
  --allow tcp:8080 \
  --source-ranges 0.0.0.0/0 \
  --target-tags webrtc-signaling
```

### Step 2: Deploy Code to VM

```bash
# SSH to the VM
gcloud compute ssh webrtc-signaling --zone=us-central1-a

# Install Node.js (on the VM)
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt-get install -y nodejs

# Clone your code and deploy
git clone <your-repository>
cd webrtc_test
npm install
npm start
```

## Update Flutter App Configuration

After deploying your signaling server, update your Flutter app:

### Step 1: Update Config

Edit `lib/config.dart`:

```dart
// Replace with your actual deployment URL
static const String productionSignalingUrl = 'wss://your-deployment-url';
```

Examples:
- **Cloud Run**: `'wss://webrtc-signaling-xxxxx-uc.a.run.app'`
- **App Engine**: `'wss://your-project-id.uc.r.appspot.com'`
- **Compute Engine**: `'wss://your-vm-external-ip:8080'`

### Step 2: Build and Test Flutter App

```bash
# Install dependencies
flutter pub get

# Build for Android
flutter build apk --release

# Or build for iOS
flutter build ios --release

# Or run in development mode
flutter run --dart-define=SIGNALING_SERVER_URL=wss://your-deployment-url
```

## Testing Your Deployment

### 1. Test Signaling Server

```bash
# Health check
curl https://your-deployment-url/health

# Should return:
# {
#   "status": "healthy",
#   "connectedUsers": 0,
#   "activeRooms": 0,
#   "timestamp": "..."
# }
```

### 2. Test WebSocket Connection

Use a WebSocket testing tool or browser console:

```javascript
const ws = new WebSocket('wss://your-deployment-url');
ws.onopen = () => console.log('Connected');
ws.onmessage = (msg) => console.log('Message:', msg.data);
ws.onclose = () => console.log('Disconnected');
```

### 3. Test Full WebRTC Flow

1. **Deploy your Flutter app** to two test devices
2. **Open the app** on both devices
3. **Tap "Join Room"** on both devices
4. **Tap "Call Peer"** on one device
5. **Verify video/audio connection**

## Network Configuration

### Firewall Rules

Ensure these ports are open:

- **Signaling Server**: Port `8080` or `443` (for HTTPS/WSS)
- **TURN Server**: Port `3478` (already configured)
- **WebRTC Media**: Ports `10000-20000` (UDP, already handled by TURN)

### SSL/TLS Configuration

For production, ensure HTTPS/WSS:

- **Cloud Run/App Engine**: Automatic HTTPS
- **Compute Engine**: Use Let's Encrypt or Cloud Load Balancer

## Monitoring and Logging

### Cloud Run/App Engine Logs

```bash
# View logs
gcloud logs read "resource.type=cloud_run_revision" --limit 50

# Or for App Engine
gcloud logs read "resource.type=gae_app" --limit 50
```

### Health Monitoring

Set up monitoring for:
- **Server uptime**: `/health` endpoint
- **WebSocket connections**: Active user count
- **Room activity**: Number of active rooms

## Cost Optimization

### Cloud Run
- **Pay per request** - ideal for variable traffic
- **Scales to zero** when not in use
- **Free tier**: 2 million requests/month

### App Engine
- **Automatic scaling** based on traffic
- **Free tier**: 28 instance hours/day

### Compute Engine
- **Fixed cost** regardless of usage
- **Preemptible instances** for cost savings
- **Right-size** your instance

## Security Considerations

### Authentication
Consider adding authentication to your signaling server:

```javascript
// Add to signaling_server.js
io.use((socket, next) => {
  const token = socket.handshake.auth.token;
  // Validate token here
  if (isValidToken(token)) {
    next();
  } else {
    next(new Error('Authentication error'));
  }
});
```

### Rate Limiting
Add rate limiting to prevent abuse:

```bash
npm install express-rate-limit
```

### CORS Configuration
Update CORS settings for production:

```javascript
const io = socketIo(server, {
  cors: {
    origin: ["https://yourdomain.com"],
    methods: ["GET", "POST"]
  }
});
```

## Troubleshooting

### Common Issues

**WebSocket Connection Failed**:
- Check HTTPS/WSS protocol
- Verify firewall rules
- Test with `curl` or WebSocket client

**No Video/Audio**:
- Ensure TURN server is accessible
- Check device permissions
- Test on real devices (not emulators)

**High Latency**:
- Choose region closer to users
- Optimize TURN server location
- Monitor network paths

### Debug Commands

```bash
# Check service status (Cloud Run)
gcloud run services describe webrtc-signaling --region us-central1

# Check VM status (Compute Engine)
gcloud compute instances list

# View real-time logs
gcloud logs tail "resource.type=cloud_run_revision"
```

## Next Steps

1. **Deploy signaling server** using your preferred method
2. **Update Flutter app** with deployment URL
3. **Test with real devices** on different networks
4. **Monitor performance** and optimize as needed
5. **Add authentication** and security features
6. **Scale** based on usage patterns

Your WebRTC app will now work globally with:
- **TURN server**: `34.71.140.192:3478` (your existing server)
- **Signaling server**: Your new GCP deployment
- **Flutter app**: Updated to use remote signaling

The complete setup enables real-time video/audio communication between users anywhere in the world!
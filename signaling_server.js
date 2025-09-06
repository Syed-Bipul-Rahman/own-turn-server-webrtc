const express = require('express');
const http = require('http');
const socketIo = require('socket.io');
const cors = require('cors');

const app = express();
const server = http.createServer(app);
const io = socketIo(server, {
  cors: {
    origin: "*",
    methods: ["GET", "POST"]
  }
});

app.use(cors());
app.use(express.json());

const PORT = process.env.PORT || 8080;

// Store connected users and rooms
const users = new Map();
const rooms = new Map();

io.on('connection', (socket) => {
  console.log('New client connected:', socket.id);

  // Handle user joining a room
  socket.on('join-room', (data) => {
    const { roomId, userId } = data;
    
    socket.join(roomId);
    users.set(socket.id, { userId, roomId });
    
    if (!rooms.has(roomId)) {
      rooms.set(roomId, new Set());
    }
    rooms.get(roomId).add(socket.id);
    
    console.log(`User ${userId} joined room ${roomId}`);
    
    // Notify others in the room
    socket.to(roomId).emit('user-joined', { userId, socketId: socket.id });
    
    // Send list of existing users in room
    const roomUsers = Array.from(rooms.get(roomId))
      .filter(id => id !== socket.id)
      .map(id => ({ socketId: id, userId: users.get(id)?.userId }));
    
    socket.emit('room-users', roomUsers);
  });

  // Handle WebRTC offer
  socket.on('offer', (data) => {
    const { offer, targetSocketId } = data;
    console.log(`Forwarding offer from ${socket.id} to ${targetSocketId}`);
    
    socket.to(targetSocketId).emit('offer', {
      offer,
      senderSocketId: socket.id
    });
  });

  // Handle WebRTC answer
  socket.on('answer', (data) => {
    const { answer, targetSocketId } = data;
    console.log(`Forwarding answer from ${socket.id} to ${targetSocketId}`);
    
    socket.to(targetSocketId).emit('answer', {
      answer,
      senderSocketId: socket.id
    });
  });

  // Handle ICE candidates
  socket.on('ice-candidate', (data) => {
    const { candidate, targetSocketId } = data;
    console.log(`Forwarding ICE candidate from ${socket.id} to ${targetSocketId}`);
    
    socket.to(targetSocketId).emit('ice-candidate', {
      candidate,
      senderSocketId: socket.id
    });
  });

  // Handle disconnect
  socket.on('disconnect', () => {
    console.log('Client disconnected:', socket.id);
    
    const user = users.get(socket.id);
    if (user) {
      const { roomId } = user;
      
      // Remove from room
      if (rooms.has(roomId)) {
        rooms.get(roomId).delete(socket.id);
        
        // Clean up empty rooms
        if (rooms.get(roomId).size === 0) {
          rooms.delete(roomId);
        }
      }
      
      // Notify others in room
      socket.to(roomId).emit('user-left', { socketId: socket.id });
      
      users.delete(socket.id);
    }
  });

  // Handle call initiation
  socket.on('initiate-call', (data) => {
    const { targetSocketId } = data;
    console.log(`Call initiated from ${socket.id} to ${targetSocketId}`);
    
    socket.to(targetSocketId).emit('incoming-call', {
      callerSocketId: socket.id
    });
  });

  // Handle call response
  socket.on('call-response', (data) => {
    const { accepted, targetSocketId } = data;
    console.log(`Call response from ${socket.id} to ${targetSocketId}: ${accepted}`);
    
    socket.to(targetSocketId).emit('call-response', {
      accepted,
      responderSocketId: socket.id
    });
  });
});

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({ 
    status: 'healthy', 
    connectedUsers: users.size,
    activeRooms: rooms.size,
    timestamp: new Date().toISOString()
  });
});

// Get room info
app.get('/rooms/:roomId', (req, res) => {
  const { roomId } = req.params;
  const room = rooms.get(roomId);
  
  if (!room) {
    return res.json({ users: [], count: 0 });
  }
  
  const roomUsers = Array.from(room).map(socketId => ({
    socketId,
    userId: users.get(socketId)?.userId
  }));
  
  res.json({ 
    users: roomUsers, 
    count: roomUsers.length 
  });
});

// Root endpoint
app.get('/', (req, res) => {
  res.json({
    service: 'WebRTC Signaling Server',
    status: 'running',
    version: '1.0.0',
    endpoints: {
      health: '/health',
      rooms: '/rooms/:roomId'
    }
  });
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`WebRTC Signaling Server running on port ${PORT}`);
  console.log(`Health check available at http://localhost:${PORT}/health`);
  console.log(`Environment: ${process.env.NODE_ENV || 'development'}`);
});
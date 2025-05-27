import 'dart:io'; // For platform-specific functionality
import 'dart:math' as math; // For math operations
import 'package:camera/camera.dart'; // For camera functionality
import 'package:flutter/foundation.dart'; // For Flutter foundation classes
import 'package:flutter/material.dart'; // For Material Design widgets
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart'; // For face detection
import 'package:permission_handler/permission_handler.dart'; // For handling permissions
import 'dart:ui' as ui; // For UI-related classes
import 'face_detection_painter.dart'; // Custom painter for face detection visualization

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Camera controller to manage camera functionality
  CameraController? _cameraController;

  // Future for camera initialization
  Future<void>? _initializeControllerFuture;

  // Face detector instance with configuration options
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableClassification: true, // Enable facial features classification
      enableLandmarks: true, // Enable facial landmarks detection
      performanceMode: FaceDetectorMode.fast, // Optimize for speed
    ),
  );

  bool isDetected = false; // Flag to prevent overlapping detections
  List<Face> _face = []; // List to store detected faces
  List<CameraDescription> cameras = []; // List of available cameras
  int _selectedCameraIndex = 0; // Index of currently selected camera

  @override
  void initState() {
    super.initState();
    _requestPermission(); // Request camera permission
    _initializedCamera(); // Initialize camera
  }

  @override
  void dispose() {
    // Clean up resources when widget is disposed
    _cameraController?.dispose();
    _faceDetector.close();
    super.dispose();
  }

  // Request camera permission from user
  Future<void> _requestPermission() async {
    final status = await Permission.camera.request();
    if (status != PermissionStatus.granted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Permission Denied")));
    }
  }

  // Initialize camera by getting available cameras
  Future<void> _initializedCamera() async {
    try {
      cameras = await availableCameras();
      if (cameras.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("No Camera Found")));
        return;
      }

      // Try to find front camera by default
      _selectedCameraIndex = cameras.indexWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
      );

      // If no front camera, use first available camera
      if (_selectedCameraIndex == -1) {
        _selectedCameraIndex = 0;
      }

      await _initializeCamera(cameras[_selectedCameraIndex]);
    } catch (e) {
      print(e);
    }
  }

  // Initialize specific camera
  Future<void> _initializeCamera(CameraDescription cameraDescription) async {
    final controller = CameraController(
      cameraDescription,
      ResolutionPreset.ultraHigh, // Use highest resolution
      enableAudio: false, // No audio needed
      imageFormatGroup:
          Platform.isIOS ? ImageFormatGroup.bgra8888 : ImageFormatGroup.yuv420,
    );

    _cameraController = controller;

    _initializeControllerFuture = controller
        .initialize()
        .then((_) {
          if (!mounted) return;
          setState(() {
            _startFaceDetection(); // Start face detection after initialization
          });
        })
        .catchError((error) {
          print(error);
        });
  }

  // Switch between front and back camera
  void _toggleCamera() async {
    if (cameras.isEmpty || cameras.length < 2) {
      print("Cannot toggle camera. Not enough cameras available");
      return;
    }

    // Stop current image stream if running
    if (_cameraController != null &&
        _cameraController!.value.isStreamingImages) {
      await _cameraController!.stopImageStream();
    }

    // Switch to next camera
    _selectedCameraIndex = (_selectedCameraIndex + 1) % cameras.length;
    setState(() {
      _face = []; // Clear previous faces
    });

    await _initializeCamera(cameras[_selectedCameraIndex]);
  }

  // Start face detection from camera stream
  void _startFaceDetection() {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    _cameraController!.startImageStream((CameraImage image) async {
      if (isDetected) return; // Prevent overlapping processing
      isDetected = true;

      // Convert camera image to MLKit input format
      final inputImage = _convertCameraImageToInputImage(image);
      if (inputImage == null) {
        isDetected = false;
        return;
      }

      try {
        // Process image for face detection
        final List<Face> faces = await _faceDetector.processImage(inputImage);
        if (mounted) {
          setState(() {
            _face = faces; // Update detected faces
          });
        }
      } catch (error) {
        print(error);
      } finally {
        isDetected = false; // Reset detection flag
      }
    });
  }

  // Convert CameraImage to InputImage format required by MLKit
  InputImage? _convertCameraImageToInputImage(CameraImage image) {
    if (_cameraController == null) return null;
    try {
      final format =
          Platform.isIOS ? InputImageFormat.bgra8888 : InputImageFormat.nv21;

      final inputImageMetaData = InputImageMetadata(
        size: ui.Size(image.width.toDouble(), image.height.toDouble()),
        rotation: InputImageRotation.values.firstWhere(
          (element) =>
              element.rawValue ==
              _cameraController!.description.sensorOrientation,
          orElse: () => InputImageRotation.rotation0deg,
        ),
        format: format,
        bytesPerRow: image.planes[0].bytesPerRow,
      );

      final bytes = _concatenatePlanes(image.planes);
      return InputImage.fromBytes(bytes: bytes, metadata: inputImageMetaData);
    } catch (error) {
      print(error);
      return null;
    }
  }

  // Combine image planes into single byte array
  Uint8List _concatenatePlanes(List<Plane> planes) {
    final allBytes = WriteBuffer();
    for (Plane plane in planes) {
      allBytes.putUint8List(plane.bytes);
    }
    return allBytes.done().buffer.asUint8List();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      /// app bar
      appBar: AppBar(
        title: const Text('ML Face Detection'),
        actions: [
          // Show camera switch button only if multiple cameras available
          if (cameras.length > 1)
            IconButton(
              icon: const Icon(Icons.cameraswitch),
              onPressed: _toggleCamera,
            ),
        ],
      ),
      body:
          _initializeControllerFuture == null
              ? Center()
              : FutureBuilder<void>(
                future: _initializeControllerFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.done &&
                      _cameraController != null &&
                      _cameraController!.value.isInitialized) {
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        // Camera preview with mirroring for front camera
                        Transform(
                          alignment: Alignment.center,
                          transform:
                              _cameraController!.description.lensDirection ==
                                      CameraLensDirection.front
                                  ? Matrix4.rotationY(
                                    math.pi,
                                  ) // Mirror for front camera
                                  : Matrix4.identity(),
                          child: CameraPreview(_cameraController!),
                        ),

                        // Custom painter for face detection visualization
                        CustomPaint(
                          painter: FaceDetectionPainter(
                            faces: _face,
                            imageSize: ui.Size(
                              _cameraController!.value.previewSize!.height,
                              _cameraController!.value.previewSize!.width,
                            ),
                            cameraLensDirection:
                                _cameraController!.description.lensDirection,
                          ),
                        ),

                        // Face count indicator at bottom
                        Positioned(
                          bottom: 20,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: Container(
                              padding: EdgeInsets.symmetric(
                                vertical: 8,
                                horizontal: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text("Face Detected ${_face.length}"),
                            ),
                          ),
                        ),
                      ],
                    );
                  } else if (snapshot.hasError) {
                    return Text("Error Found");
                  } else {
                    return Center(child: CircularProgressIndicator());
                  }
                },
              ),
    );
  }
}

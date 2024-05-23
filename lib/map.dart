import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class MapsPage extends StatefulWidget {
  final String firestoreUserID;

  MapsPage({required this.firestoreUserID});

  @override
  State<MapsPage> createState() => _MapsPageState();
}

class _MapsPageState extends State<MapsPage> {
  Position? userLocation;
  late GoogleMapController mapController;
  late DatabaseReference userRef;
  Timer? locationUpdateTimer;
  Map<String, LatLng> friendsLocations = {};
  Map<String, String> friendsUsernames = {};
  bool locationUpdatesEnabled = true;

  @override
  void initState() {
    super.initState();
    _initializeUser();
  }

  @override
  void dispose() {
    locationUpdateTimer?.cancel();
    super.dispose();
  }

  Future<void> _initializeUser() async {
    try {
      DocumentSnapshot userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.firestoreUserID)
          .get();
      if (userDoc.exists) {
        var userData = userDoc.data() as Map<String, dynamic>;
        var userName = userData['username'];
        var userId = userData['userId'];

        userRef = FirebaseDatabase.instance.ref('users/$userId');

        if (locationUpdatesEnabled) {
          await setLocation(userName, userId);
        }

        await _getFriendsLocations();
      } else {
        print("No user data found");
      }
    } catch (e) {
      print("Error initializing user: $e");
    }
  }

  void _onMapCreated(GoogleMapController controller) {
    mapController = controller;
  }

  Future<void> setLocation(String userName, String userId) async {
    final position = await _getLocation();
    if (position != null) {
      setState(() {
        userLocation = position;
      });

      locationUpdateTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
        if (locationUpdatesEnabled) {
          final updatedPosition = await _getLocation();
          if (updatedPosition != null) {
            userRef.update({
              'username': userName,
              'userId': userId,
              'latitude': updatedPosition.latitude,
              'longitude': updatedPosition.longitude,
            });
            setState(() {
              userLocation = updatedPosition;
            });
          }
        }
      });
    }
  }

  Future<void> _getFriendsLocations() async {
    try {
      QuerySnapshot friendsSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.firestoreUserID)
          .collection('friends')
          .get();

      for (var doc in friendsSnapshot.docs) {
        var friendId = doc['userId'];
        var friendUsername = doc['username'];

        DatabaseReference friendRef =
            FirebaseDatabase.instance.ref('users/$friendId');
        friendRef.onValue.listen((event) {
          var friendData = event.snapshot.value as Map<dynamic, dynamic>;
          var latitude = friendData['latitude'];
          var longitude = friendData['longitude'];

          setState(() {
            friendsLocations[friendId] = LatLng(latitude, longitude);
            friendsUsernames[friendId] = friendUsername;
          });
        });
      }
    } catch (e) {
      print("Error getting friend locations: $e");
    }
  }

  Future<Position?> _getLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return Future.error('Location services are disabled.');
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return Future.error('Location permissions are denied');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return Future.error(
          'Location permissions are permanently denied, we cannot request permissions.');
    }

    return await Geolocator.getCurrentPosition();
  }

  Set<Marker> _createFriendMarkers() {
    return friendsLocations.entries.map((entry) {
      String friendId = entry.key;
      LatLng position = entry.value;
      String? username = friendsUsernames[friendId];

      return Marker(
        markerId: MarkerId('friend_marker_$friendId'),
        position: position,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),

        // show info window when tapped
        infoWindow: InfoWindow(
          title: username ?? 'Unknown',
        ),
        onTap: () {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(username ?? 'Unknown')),
          );
        },

      );
    }).toSet();
  }

  void _toggleLocationUpdates() {
    setState(() {
      locationUpdatesEnabled = !locationUpdatesEnabled;
    });
    if (locationUpdatesEnabled) {
      _initializeUser();
    } else {
      locationUpdateTimer?.cancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Maps'),
        actions: [
          IconButton(
            icon: Icon(locationUpdatesEnabled ? Icons.location_off : Icons.location_on),
            onPressed: _toggleLocationUpdates,
          ),
        ],
      ),
      body: userLocation == null
          ? const Center(child: CircularProgressIndicator())
          : GoogleMap(
              mapType: MapType.normal,
              onMapCreated: _onMapCreated,
              initialCameraPosition: CameraPosition(
                target: LatLng(userLocation!.latitude, userLocation!.longitude),
                zoom: 18,
              ),
              markers: {
                Marker(
                  markerId: const MarkerId('user_marker'),
                  position: LatLng(userLocation!.latitude, userLocation!.longitude),
                  icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
                ),
                ..._createFriendMarkers(),
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          if (userLocation != null) {
            mapController.animateCamera(CameraUpdate.newLatLng(
              LatLng(userLocation!.latitude, userLocation!.longitude),
            ));
          }
        },
        child: const Icon(Icons.my_location),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}

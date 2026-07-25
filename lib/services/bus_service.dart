import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:agni_college_bus_tracker/models/bus.dart';

class BusService extends ChangeNotifier {
  static const _busesKey = 'buses';
  List<Bus> _buses = [];

  List<Bus> get buses => _buses;

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final busesJson = prefs.getString(_busesKey);

    if (busesJson != null) {
      try {
        final List decoded = json.decode(busesJson);
        _buses = decoded.map((e) => Bus.fromJson(e)).toList();
      } catch (e) {
        debugPrint('Error loading buses: $e');
        await _loadDefaultBuses();
      }
    } else {
      await _loadDefaultBuses();
    }
    notifyListeners();
  }

  Future<void> _loadDefaultBuses() async {
    _buses = [
      Bus(
          id: 1,
          busNumber: '1',
          route: 'Minjur',
          driverName: 'Mr. Mohan',
          driverPhone: '9940140579',
          stops: ['Minjur', 'Ennore', 'College']),
      Bus(
          id: 2,
          busNumber: '2',
          route: 'Karmbakkam',
          driverName: 'Mr. Annamalai',
          driverPhone: '8098587815',
          stops: ['Karmbakkam', 'Porur', 'College']),
      Bus(
          id: 3,
          busNumber: '3',
          route: 'Poonamallee',
          driverName: 'Mr. Ashok',
          driverPhone: '9841471087',
          stops: ['Poonamallee', 'Vadapalani', 'College']),
      Bus(
          id: 4,
          busNumber: '4',
          route: 'Thiruvallur',
          driverName: 'Mr. Arumugam',
          driverPhone: '9092348973',
          stops: ['Thiruvallur', 'Avadi', 'College']),
      Bus(
          id: 5,
          busNumber: '5',
          route: 'Redhills',
          driverName: 'Mr. Jayavel',
          driverPhone: '9841145251',
          stops: ['Redhills', 'Ambattur', 'College']),
      Bus(
          id: 6,
          busNumber: '6',
          route: 'Kuvathur',
          driverName: 'Mr. Saravanan',
          driverPhone: '9962258073',
          stops: ['Kuvathur', 'Guduvanchery', 'College']),
      Bus(
          id: 7,
          busNumber: '7',
          route: 'Chengalpattu Court',
          driverName: 'Mr. Lakshmanan',
          driverPhone: '9087233747',
          stops: ['Chengalpattu', 'Tambaram', 'College']),
      Bus(
          id: 8,
          busNumber: '8',
          route: 'Iyyappanthangal',
          driverName: 'Mr. Arul Raj',
          driverPhone: '8438037502',
          stops: ['Iyyappanthangal', 'Porur', 'College']),
      Bus(
          id: 9,
          busNumber: '9',
          route: 'Manali Indian Oil',
          driverName: 'Mr. Senthil Kumar',
          driverPhone: '8939408448',
          stops: ['Manali', 'Madhavaram', 'College']),
      Bus(
          id: 10,
          busNumber: '10',
          route: 'Perambur',
          driverName: 'Mr. Raja Babu',
          driverPhone: '9092441577',
          stops: ['Perambur', 'Central', 'College']),
      Bus(
          id: 11,
          busNumber: '11',
          route: 'Thalankuppam',
          driverName: 'Mr. Moideen',
          driverPhone: '6381281050',
          stops: ['Thalankuppam', 'Kelambakkam', 'College']),
      Bus(
          id: 12,
          busNumber: '12',
          route: 'Velappachavadi',
          driverName: 'Mr. Danal Durai',
          driverPhone: '9171441799',
          stops: ['Velappachavadi', 'Ambattur', 'College']),
      Bus(
          id: 13,
          busNumber: '13',
          route: 'Thiruvanmiyur',
          driverName: 'Mr. Puniyanathan',
          driverPhone: '8939248108',
          stops: ['Thiruvanmiyur', 'Adyar', 'College']),
      Bus(
          id: 14,
          busNumber: '14',
          route: 'Baby Nagar',
          driverName: 'Mr. Selvaraj',
          driverPhone: '9941737721',
          stops: ['Baby Nagar', 'Perungudi', 'College']),
      Bus(
          id: 15,
          busNumber: '15',
          route: 'Sriperumbudur',
          driverName: 'Mr. Rohith',
          driverPhone: '6380555737',
          stops: ['Sriperumbudur', 'Oragadam', 'College']),
      Bus(
          id: 16,
          busNumber: '16',
          route: 'Chrompet',
          driverName: 'Mr. Siva',
          driverPhone: '7845322390',
          stops: ['Chrompet', 'Pallavaram', 'College']),
      Bus(
          id: 17,
          busNumber: '17',
          route: 'Little Mount',
          driverName: 'Mr. Mani',
          driverPhone: '8098923973',
          stops: ['Little Mount', 'Guindy', 'College']),
      Bus(
          id: 18,
          busNumber: '18',
          route: 'Vettuvankeni',
          driverName: 'Mr. Vinoth',
          driverPhone: '6379214121',
          stops: ['Vettuvankeni', 'Neelankarai', 'College']),
      Bus(
          id: 19,
          busNumber: '19',
          route: 'Kasi Theatre',
          driverName: 'Mr. Elumalai',
          driverPhone: '9710234783',
          stops: ['Kasi Theatre', 'Aminjikarai', 'College']),
      Bus(
          id: 20,
          busNumber: '20',
          route: 'Kanthanchavadi',
          driverName: 'Mr. Sadhik',
          driverPhone: '8939594677',
          stops: ['Kanthanchavadi', 'Perungudi', 'College']),
      Bus(
          id: 21,
          busNumber: '21',
          route: 'Vallam',
          driverName: 'Mr. Murugan',
          driverPhone: '8680040406',
          stops: ['Vallam', 'Chengalpattu', 'College']),
      Bus(
          id: 22,
          busNumber: '22',
          route: 'Mint',
          driverName: 'Mr. Kannan',
          driverPhone: '9384642621',
          stops: ['Mint', 'Park Town', 'College']),
      Bus(
          id: 23,
          busNumber: '23',
          route: 'Chepauk VM Office',
          driverName: 'Mr. Ram Kumar',
          driverPhone: '9345084612',
          stops: ['Chepauk', 'Triplicane', 'College']),
      Bus(
          id: 24,
          busNumber: '24',
          route: 'Saidapet',
          driverName: 'Mr. Srinivasan',
          driverPhone: '9677261986',
          stops: ['Saidapet', 'Guindy', 'College']),
      Bus(
          id: 25,
          busNumber: '25',
          route: 'Urapakkam',
          driverName: 'Mr. Sudhakar',
          driverPhone: '9159675707',
          stops: ['Urapakkam', 'Guduvanchery', 'College']),
      Bus(
          id: 26,
          busNumber: '26',
          route: 'Mudichur Atta Company',
          driverName: 'Mr. Karthi',
          driverPhone: '9884332286',
          stops: ['Mudichur', 'Tambaram', 'College']),
      Bus(
          id: 27,
          busNumber: '27',
          route: 'Panaiyur',
          driverName: 'Mr. Selvaraj',
          driverPhone: '9941737872',
          stops: ['Panaiyur', 'Sholinganallur', 'College']),
      Bus(
          id: 28,
          busNumber: '28',
          route: 'Kaiveli',
          driverName: null,
          driverPhone: null,
          stops: ['Kaiveli', 'Mahabalipuram', 'College']),
      Bus(
          id: 29,
          busNumber: '29',
          route: 'Thiruporur',
          driverName: 'Mr. Vadivel',
          driverPhone: '9884731006',
          stops: ['Thiruporur', 'Kelambakkam', 'College']),
      Bus(
          id: 30,
          busNumber: '30',
          route: 'Royapuram',
          driverName: 'Mr. Vignesh',
          driverPhone: '9842983729',
          stops: ['Royapuram', 'Washermanpet', 'College']),
      Bus(
          id: 31,
          busNumber: '31',
          route: 'Jeyachandran Pallikaranai',
          driverName: 'Mr. Murali',
          driverPhone: '9952943617',
          stops: ['Pallikaranai', 'Velachery', 'College']),
      Bus(
          id: 32,
          busNumber: '32',
          route: 'NIOT',
          driverName: null,
          driverPhone: null,
          stops: ['NIOT', 'Pallikaranai', 'College']),
    ];
    await _saveBuses();
  }

  Future<void> _saveBuses() async {
    final prefs = await SharedPreferences.getInstance();
    final busesJson = json.encode(_buses.map((e) => e.toJson()).toList());
    await prefs.setString(_busesKey, busesJson);
  }

  Bus? getBusByNumber(String busNumber) {
    try {
      return _buses.firstWhere((b) => b.busNumber == busNumber);
    } on StateError {
      return null;
    }
  }

  Future<void> addBus(Bus bus) async {
    _buses.add(bus);
    await _saveBuses();
    notifyListeners();
  }

  Future<void> updateBus(Bus bus) async {
    final index = _buses.indexWhere((b) => b.busNumber == bus.busNumber);
    if (index != -1) {
      _buses[index] = bus;
      await _saveBuses();
      notifyListeners();
    }
  }

  Future<void> deleteBus(String busNumber) async {
    _buses.removeWhere((b) => b.busNumber == busNumber);
    await _saveBuses();
    notifyListeners();
  }
}

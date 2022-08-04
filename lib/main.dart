import 'package:flutter/material.dart';
import 'dart:async';
import 'package:intl/intl.dart';
import 'dart:math';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Current Color',
      theme: ThemeData(
        primaryColor: Colors.black,
        fontFamily: 'RictyDiminished',
        textTheme: const TextTheme(
          headline1: TextStyle(color: Colors.white70),
          headline2: TextStyle(color: Colors.white70),
          headline3: TextStyle(color: Colors.white70),
          headline5: TextStyle(color: Colors.white70),
          headline6: TextStyle(color: Colors.white70),
        ),
      ),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key}) : super(key: key);

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  String _timeStr = '';
  String _msStr = '';
  String _dateStr = '';
  Color _sBgColor = Colors.transparent;
  final Color _eBgColor = Colors.black54;

  @override
  void initState() {
    super.initState();

    Timer.periodic(const Duration(milliseconds: 10), _onTimer);
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Container(
            width: MediaQuery.of(context).size.width,
            height: MediaQuery.of(context).size.height,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  _eBgColor,
                  _sBgColor,
                  _sBgColor,
                  _sBgColor,
                  _eBgColor,
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
          Center(
            child: Container(
              width: MediaQuery.of(context).size.width * 0.6,
              padding: const EdgeInsets.all(50.0),
              decoration: BoxDecoration(
                border: Border.all(
                  color: Colors.white24,
                  width: 4,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _dateStr.toString(),
                    style: Theme.of(context).textTheme.headline6,
                  ),
                  Text(
                    _timeStr,
                    style: Theme.of(context).textTheme.headline1,
                  ),
                  Text(
                    '.$_msStr',
                    style: Theme.of(context).textTheme.headline6,
                  ),
                  Text(
                    '${_sBgColor.toString().split('(')[0]}(0x${_sBgColor.toString().split('x')[1].toUpperCase()}',
                    style: Theme.of(context).textTheme.headline3,
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            child: Container(
              width: MediaQuery.of(context).size.width,
              height: MediaQuery.of(context).size.height * 0.05,
              color: Colors.black,
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            child: Container(
              width: MediaQuery.of(context).size.width,
              height: MediaQuery.of(context).size.height * 0.05,
              color: Colors.black,
            ),
          )
        ],
      ),
    );
  }

  void _onTimer(Timer timer) {
    var now = DateTime.now();
    var timeString = DateFormat('HH:mm:ss').format(now);
    var dateString = DateFormat('yyyy-MM-dd').format(now);
    var millisecondsString = DateFormat('S').format(now);

    var hue = ((now.toLocal().millisecondsSinceEpoch / 1000) % 360);

    var startBackgroundColor = HSLColor.fromAHSL(
      0.4 + Random().nextDouble() * 0.00198,
      hue,
      0.5 + Random().nextDouble() * 0.001,
      0.8 + Random().nextDouble() * 0.001,
    ).toColor();

    setState(() => {
          _timeStr = timeString,
          _msStr = millisecondsString,
          _dateStr = dateString,
          _sBgColor = startBackgroundColor,
          //_eBgColor = startBackgroundColor,
        });
  }
}

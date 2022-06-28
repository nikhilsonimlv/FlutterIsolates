import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:developer' as devtools show log;
import 'package:async/async.dart' show StreamGroup;

import 'package:flutter/material.dart';

extension Log on Object {
  void log() => devtools.log(toString());
}

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // Try running your application with "flutter run". You'll see the
        // application has a blue toolbar. Then, without quitting the app, try
        // changing the primarySwatch below to Colors.green and then invoke
        // "hot reload" (press "r" in the console where you ran "flutter run",
        // or simply save your changes to "hot reload" in a Flutter IDE).
        // Notice that the counter didn't reset back to zero; the application
        // is not restarted.
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(),
    );
  }
}

@immutable
class Person {
  final String name;
  final int age;
  const Person({required this.name, required this.age});

  Person.fromJson(Map<String, dynamic> json)
      : name = json["name"] as String,
        age = json["age"] as int;

  @override
  String toString() {
    return 'Person(name : $name, age: $age)';
  }
}

// Example one
Future<Iterable<Person>> getPerson() async {
  final rp = ReceivePort();
  await Isolate.spawn(_getPersons, rp.sendPort);
  return await rp.first;
}

void _getPersons(SendPort sp) async {
  const url = "http://10.0.2.2:5500/apis/people1.json";
  final persons = await HttpClient()
      .getUrl(Uri.parse(url))
      .then((req) => req.close())
      .then((response) => response.transform(utf8.decoder).join())
      .then((jsonString) => json.decode(jsonString) as List<dynamic>)
      .then((json) => json.map((map) => Person.fromJson(map)));

  Isolate.exit(sp, persons);
}

//////////////////////////////////////////////////////////
///
///Example Two
Stream<String> getMessages() {
  final rp = ReceivePort();
  return Isolate.spawn(_getMessages, rp.sendPort)
      .asStream()
      .asyncExpand((_) => rp)
      .takeWhile((element) => element is String)
      .cast();
}

void _getMessages(SendPort sp) async {
  await for (final now in Stream.periodic(Duration(seconds: 1),
      (computationCount) => DateTime.now().toIso8601String()).take(10)) {
    sp.send(now);
  }
  Isolate.exit(sp);
}

void testIt() async {
  await for (final message in getMessages()) {
    message.log();
  }
}

//////////////////////////////////////////////////////////
///Example Three
@immutable
class Request {
  final SendPort sp;
  final Uri uri;
  const Request(this.sp, this.uri);

  Request.from(PersonRequest request)
      : sp = request.rp.sendPort,
        uri = request.uri;
}

@immutable
class PersonRequest {
  final ReceivePort rp;
  final Uri uri;
  const PersonRequest(this.rp, this.uri);

  static Iterable<PersonRequest> all() sync* {
    for (final i in Iterable.generate(3, ((index) => index))) {
      yield PersonRequest(
          ReceivePort(),
          Uri.parse(
            "http://10.0.2.2:5500/apis/people${i + 1}.json",
          ));
    }
  }
}

Stream<Iterable<Person>> getMorePersons() {
  final streams = PersonRequest.all().map((req) =>
      Isolate.spawn(_getMorePersons, Request.from(req))
          .asStream()
          .asyncExpand((event) => req.rp)
          .takeWhile((element) => element is Iterable<Person>)
          .cast());
  return StreamGroup.merge(streams).cast();
}

void _getMorePersons(Request request) async {
  final persons = await HttpClient()
      .getUrl(request.uri)
      .then((req) => req.close())
      .then((response) => response.transform(utf8.decoder).join())
      .then((jsonString) => json.decode(jsonString) as List<dynamic>)
      .then(
        (value) => value.map(
          (e) => Person.fromJson(e),
        ),
      );
  Isolate.exit(request.sp, persons);
}

void testItMorePersons() async {
  await for (final message in getMorePersons()) {
    message.log();
  }
}

class MyHomePage extends StatelessWidget {
  const MyHomePage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("HomePage"),
      ),
      body: Column(
        children: [
          TextButton(
            onPressed: () {
              testIt();
            },
            child: const Text("Get Messages"),
          ),
          TextButton(
            onPressed: () async {
              final persons = await getPerson();
              persons.log();
            },
            child: const Text("Get Person"),
          ),
          TextButton(
            onPressed: () async {
              testItMorePersons();
            },
            child: const Text("Get More Person"),
          )
        ],
      ),
    );
  }
}

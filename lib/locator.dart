import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

class UnityAssetServer {
  UnityAssetServer(this._server);
  final HttpServer _server;
  int get port => _server.port;

  Future<void> stop() async => _server.close(force: true);
}


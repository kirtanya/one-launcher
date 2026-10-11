import 'dart:io';

import 'package:flutter/widgets.dart';

/// The photo at [path], or null if the file is gone (e.g. app data cleared).
ImageProvider? photoFile(String path) => File(path).existsSync() ? FileImage(File(path)) : null;

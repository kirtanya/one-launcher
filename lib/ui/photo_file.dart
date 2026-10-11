// The launcher background photo is a file on the phone; the web demo has no files.
export 'photo_file_web.dart' if (dart.library.io) 'photo_file_io.dart';

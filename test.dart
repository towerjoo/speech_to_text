// Copyright (c) 2015, the Dart project authors.
// Please see the AUTHORS file for details.
// All rights reserved. Use of this source code is governed
// by a BSD-style license that can be found in the LICENSE file.

import 'package:speech_to_text/src/speech_to_text.dart';
import 'dart:io';

main() async {
  SpeechToText speechToText = SpeechToText();
  Stream<List<int>> audioStream =
      File("/Users/tao/shadow/speech_to_text/lib/commercial_mono.wav")
          .openRead();
  await for (var x in speechToText.convert(audioStream, sampleRate: 8000)) {
    if (x['isFinal']) {
      print(x["transcript"]);
    }
  }
}

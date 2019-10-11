import 'package:grpc/grpc.dart';

import 'generated/google/cloud/speech/v1/cloud_speech.pbgrpc.dart';

class SpeechToText {
  String credentials;
  SpeechToText({this.credentials});
  Stream<Map> convert(Stream<List<int>> audioStream,
      {int sampleRate = 16000, langCode = 'en-US'}) async* {
    var scopes = ["https://www.googleapis.com/auth/cloud-platform"];
    final authenticator = ServiceAccountAuthenticator(credentials, scopes);
    ClientChannel channel = ClientChannel('speech.googleapis.com');

    SpeechClient speechClient =
        SpeechClient(channel = channel, options: authenticator.toCallOptions);

    var requestStream = getStreamingRequest(audioStream, sampleRate, langCode)
        .asBroadcastStream();
    await for (var resp in speechClient.streamingRecognize(requestStream)) {
      int numCharsPrinted = 0;
      String overwriteChars = "";
      if (resp.results.length > 0) {
        var result = resp.results[0];
        if (result.alternatives.length > 0) {
          var transcript = result.alternatives[0].transcript;
          overwriteChars = ' ' * (numCharsPrinted - transcript.length);
          yield {
            'transcript': transcript + overwriteChars,
            'isFinal': result.isFinal
          };
        }
      }
    }
  }

  Stream<List<int>> patchStream(
      Stream<List<int>> inputStream, int chunkSize) async* {
    List<int> temp = [];
    await for (var chunk in inputStream) {
      temp.addAll(chunk);
      while (true) {
        if (temp.length < chunkSize) {
          break;
        }
        List<int> outputChunk = temp.getRange(0, chunkSize).toList();
        temp.removeRange(0, chunkSize);
        yield outputChunk;
      }
    }
  }

  Stream<StreamingRecognizeRequest> getStreamingRequest(
      Stream<List<int>> audioStream, int sampleRate, String langCode) async* {
    RecognitionConfig config = RecognitionConfig();
    config
      ..encoding = RecognitionConfig_AudioEncoding.LINEAR16
      ..sampleRateHertz = sampleRate
      ..enableAutomaticPunctuation = true
      ..languageCode = langCode;
    StreamingRecognitionConfig streamingRecognitionConfig =
        StreamingRecognitionConfig();
    streamingRecognitionConfig.config = config;
    streamingRecognitionConfig.interimResults = true;
    var req = StreamingRecognizeRequest()
      ..streamingConfig = streamingRecognitionConfig;
    yield req;
    int chunkSize = sampleRate ~/ 10; // 100ms
    Stream<List<int>> patchedStream = patchStream(audioStream, chunkSize);
    await for (var audio in patchedStream) {
      var req = StreamingRecognizeRequest()..audioContent = audio;
      yield req;
    }
  }
}

import 'package:grpc/grpc.dart';
import 'package:googleapis_auth/auth.dart' show AccessToken;
import 'generated/google/cloud/speech/v1/cloud_speech.pbgrpc.dart';

class SpeechToTextAuthenticator extends BaseAuthenticator {
  AccessToken _accessToken;
  Future<Map> Function() _fetchToken;
  static int tryTimes = 0;
  SpeechToTextAuthenticator(Future<Map> Function() fetchToken) {
    // Map token = {
    //   "token":
    //       "ya29.c.Kl6wB7DgqIMjOqylrPDX1dC7P-Xnrqm8AFDmglESLghkM1rL8TycgFPGHXan1H45lUJrvN8_xrkD_qK8t_EoPVQCvzpuFiqqL_5VGpPJL-hk8G9Gg9NepwjgDfie9e2X",
    //   "expiry": "2019-11-06 09:52:06.369570"
    // };
    _fetchToken = fetchToken;
  }
  Future<void> authenticate(Map<String, String> metadata, String uri) async {
    Map token = await _fetchToken();
    DateTime expiry = DateTime.parse(token["expiry"]).toUtc();
    _accessToken = AccessToken("Bearer", token["token"], expiry);
    final auth = '${_accessToken.type} ${_accessToken.data}';
    metadata['authorization'] = auth;
    if (_tokenExpiresSoon) {
      // Token is about to expire. Extend it prematurely.
      if (tryTimes >= 3) {
        // avoid the dead lock
        return;
      }
      tryTimes++;
      await authenticate(metadata, uri);
      // obtainAccessCredentials(_lastUri).catchError((_) {});
    }
  }

  bool get _tokenExpiresSoon => _accessToken.expiry
      .subtract(Duration(seconds: 30))
      .isBefore(DateTime.now().toUtc());

  Future<void> obtainAccessCredentials(String uri) async {
    return null;
  }
}

class SpeechToText {
  String credentials;
  String authType;
  Future<Map> Function() fetchToken;
  SpeechToText({this.credentials}) {
    this.authType = "account";
  }
  SpeechToText.initWithAccount({String credentials}) {
    this.authType = "account";
    this.credentials = credentials;
  }
  SpeechToText.initWithToken({Future<Map> Function() fetchToken}) {
    this.authType = "token";
    this.fetchToken = fetchToken;
  }
  Stream<Map> convert(Stream<List<int>> audioStream,
      {int sampleRate = 16000, langCode = 'en-US'}) async* {
    var scopes = ["https://www.googleapis.com/auth/cloud-platform"];
    var authenticator;
    if (authType == "account") {
      authenticator = ServiceAccountAuthenticator(credentials, scopes);
    } else {
      authenticator = SpeechToTextAuthenticator(fetchToken);
    }
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

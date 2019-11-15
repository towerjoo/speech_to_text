import 'dart:async';

import 'package:grpc/grpc.dart';
import 'package:googleapis_auth/auth.dart' show AccessToken;
import 'generated/google/cloud/speech/v1/cloud_speech.pbgrpc.dart';

enum MODEL_TYPE { DEFAULT, PHONE_CALL, VIDEO, COMMAND_AND_SEARCH }

String getModelName(MODEL_TYPE model) {
  String modelName = "default";
  switch (model) {
    case MODEL_TYPE.PHONE_CALL:
      modelName = "phone_call";
      break;
    case MODEL_TYPE.COMMAND_AND_SEARCH:
      modelName = "command_and_search";
      break;
    case MODEL_TYPE.VIDEO:
      modelName = "video";
      break;
    case MODEL_TYPE.DEFAULT:
      modelName = "default";
      break;
    default:
      modelName = "default";
      break;
  }
  return modelName;
}

class SpeechToTextAuthenticator extends BaseAuthenticator {
  AccessToken _accessToken;
  Future<Map> Function() _fetchToken;
  static int tryTimes = 0;
  Map _token;
  String type;
  SpeechToTextAuthenticator(Future<Map> Function() fetchToken) {
    // Map token = {
    //   "token":
    //       "ya29.c.Kl6wB7DgqIMjOqylrPDX1dC7P-Xnrqm8AFDmglESLghkM1rL8TycgFPGHXan1H45lUJrvN8_xrkD_qK8t_EoPVQCvzpuFiqqL_5VGpPJL-hk8G9Gg9NepwjgDfie9e2X",
    //   "expiry": "2019-11-06 09:52:06.369570"
    // };
    _fetchToken = fetchToken;
    type = "callback";
  }
  SpeechToTextAuthenticator.initWithToken(this._token) {
    type = "token";
  }
  Future<void> authenticate(Map<String, String> metadata, String uri) async {
    Map token;
    if (type == "token") {
      token = this._token;
    } else {
      token = await _fetchToken();
    }
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
  static const int STREAM_LIMIT = 29000; // in ms, 30s at most
  String credentials;
  String authType;
  Future<Map> Function() fetchToken;
  Map fetchedToken;

  DateTime startTime;

  bool isClosed = false;

  bool isInitial = true;
  int pendingSessions = 0;

  @Deprecated(
      "this function is deprecated, please use initWithFetchedToken instead")
  SpeechToText({this.credentials}) {
    this.authType = "account";
  }
  @Deprecated(
      "this function is deprecated, please use initWithFetchedToken instead")
  SpeechToText.initWithAccount({String credentials}) {
    this.authType = "account";
    this.credentials = credentials;
  }
  @Deprecated(
      "this function is deprecated, please use initWithFetchedToken instead")
  SpeechToText.initWithToken({Future<Map> Function() fetchToken}) {
    this.authType = "token";
    this.fetchToken = fetchToken;
  }
  SpeechToText.initWithFetchedToken({Map fetchedToken}) {
    this.authType = "fetchedToken";
    this.fetchedToken = fetchedToken;
  }
  Stream<Map> convert(Stream<List<int>> audioStream,
      {int sampleRate = 16000,
      String langCode = 'en-US',
      MODEL_TYPE modelType = MODEL_TYPE.DEFAULT,
      useEnhanced = false}) async* {
    var scopes = ["https://www.googleapis.com/auth/cloud-platform"];
    var authenticator;
    if (authType == "account") {
      authenticator = ServiceAccountAuthenticator(credentials, scopes);
    } else if (authType == "fetchedToken") {
      authenticator =
          SpeechToTextAuthenticator.initWithToken(this.fetchedToken);
    } else {
      authenticator = SpeechToTextAuthenticator(fetchToken);
    }
    ClientChannel channel = ClientChannel('speech.googleapis.com');

    SpeechClient speechClient =
        SpeechClient(channel = channel, options: authenticator.toCallOptions);
    StreamController<StreamingRecognizeRequest> requestController =
        StreamController();
    Stream<StreamingRecognizeResponse> responseStream;

    startTime = DateTime.now();
    audioStream.listen((audio) {
      print("audio stream: ${audio.length}");
      if (isInitial ||
          DateTime.now().difference(startTime).inMilliseconds >= STREAM_LIMIT) {
        if (!isInitial) {
          requestController.close();
          requestController = StreamController();
          print("created a new session");
        }
        isInitial = false;
        startTime = DateTime.now();
        requestController.add(
            getRequestConfig(sampleRate, langCode, modelType, useEnhanced));
        pendingSessions += 1;
        print("pending sessions after adding: $pendingSessions");
      }
      requestController.add(getRequestData(audio));
    }, onDone: () {
      print("audio is closed");
      isClosed = true;
      requestController.close();
    });
    int session = 0;
    while (true) {
      session += 1;
      print("current session: $session");
      responseStream =
          speechClient.streamingRecognize(requestController.stream);
      await for (var resp in responseStream) {
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
      pendingSessions--;
      print("pending sessions after substracting: $pendingSessions");
      if (pendingSessions == 0) {
        print("there's no pending sessions now, clean up");
        // requestController.close();
        break;
      }
    }
  }

  StreamingRecognizeRequest getRequestConfig(
      int sampleRate, String langCode, MODEL_TYPE modelType, bool useEnhanced) {
    RecognitionConfig config = RecognitionConfig();
    config
      ..encoding = RecognitionConfig_AudioEncoding.LINEAR16
      ..sampleRateHertz = sampleRate
      ..enableAutomaticPunctuation = true
      ..model = getModelName(modelType)
      ..useEnhanced = useEnhanced
      ..languageCode = langCode;
    StreamingRecognitionConfig streamingRecognitionConfig =
        StreamingRecognitionConfig();
    streamingRecognitionConfig.config = config;
    streamingRecognitionConfig.interimResults = true;
    var req = StreamingRecognizeRequest()
      ..streamingConfig = streamingRecognitionConfig;
    return req;
  }

  StreamingRecognizeRequest getRequestData(List<int> audio) {
    var req = StreamingRecognizeRequest()..audioContent = audio;
    return req;
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

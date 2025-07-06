import 'package:azure_speech_recognition_null_safety/azure_speech_recognition_null_safety.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class ContinuousRecognitionScreen extends StatefulWidget {
  @override
  _ContinuousRecognitionScreenState createState() =>
      _ContinuousRecognitionScreenState();
}

class _ContinuousRecognitionScreenState
    extends State<ContinuousRecognitionScreen> {
  bool _isMicOn = false;
  String _intermediateResult = '';
  String _recognizedText = '';

  final AzureSpeechRecognition _azureSpeechRecognition =
      AzureSpeechRecognition();

  @override
  void initState() {
    super.initState();

    AzureSpeechRecognition.initialize(
      dotenv.get('AZURE_KEY'),
      dotenv.get('AZURE_REGION'),
      lang: 'en-US',
      timeout: '1500',
    );

    // Handles interim recognition result
    _azureSpeechRecognition.setRecognitionResultHandler((text) {
      setState(() {
        _intermediateResult = text;
      });
    });

    // Handles final recognized text
    _azureSpeechRecognition.setFinalTranscription((text) {
      if (text.isEmpty) return;
      setState(() {
        _recognizedText += " $text";
        _intermediateResult = '';
      });
    });

    // Handles diarized speaker result
    _azureSpeechRecognition.setSpeakerDiarizationHandler((speakerTaggedText) {
      if (speakerTaggedText.isEmpty) return;
      setState(() {
        _recognizedText += "\n$speakerTaggedText";
        _intermediateResult = '';
      });
    });

    // Handles recognition started
    _azureSpeechRecognition.setRecognitionStartedHandler(() {
      debugPrint("Speech recognition has started.");
    });

    // Handles recognition stopped
    _azureSpeechRecognition.setRecognitionStoppedHandler(() {
      debugPrint("Speech recognition has stopped.");
    });

    // Handles errors
    _azureSpeechRecognition.onExceptionHandler((exception) {
      debugPrint("Speech recognition exception: $exception");
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Continuous Recognition'),
      ),
      body: Column(
        children: [
          SizedBox(height: 20),
          GestureDetector(
            onTap: () {
              setState(() {
                _isMicOn = !_isMicOn;
              });
              AzureSpeechRecognition.continuousRecording();
            },
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isMicOn ? Colors.green : Colors.red,
              ),
              child: Icon(
                _isMicOn ? Icons.mic : Icons.mic_off,
                color: Colors.white,
                size: 40,
              ),
            ),
          ),
          SizedBox(height: 20),
          Text('Recognizing: $_intermediateResult'),
          SizedBox(height: 20),
          Expanded(
            child: TextField(
              readOnly: true,
              maxLines: null,
              decoration: InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Transcription with Speaker',
              ),
              controller: TextEditingController(text: _recognizedText),
            ),
          ),
        ],
      ),
    );
  }
}



// import 'package:azure_speech_recognition_null_safety/azure_speech_recognition_null_safety.dart';
// import 'package:flutter/material.dart';
// import 'package:flutter_dotenv/flutter_dotenv.dart';

// class ContinuousRecognitionScreen extends StatefulWidget {
//   @override
//   _ContinuousRecognitionScreenState createState() =>
//       _ContinuousRecognitionScreenState();
// }

// class _ContinuousRecognitionScreenState
//     extends State<ContinuousRecognitionScreen> {
//   bool _isMicOn = false;
//   String _intermediateResult = '';
//   String _recognizedText = '';

//   @override
//   void initState() {
//     super.initState();
//     final AzureSpeechRecognition _azureSpeechRecognition =
//         AzureSpeechRecognition();
//     AzureSpeechRecognition.initialize(
//         dotenv.get('AZURE_KEY'), dotenv.get('AZURE_REGION'),
//         lang: 'en-US', timeout: '1500');
//     _azureSpeechRecognition.setFinalTranscription((text) {
//       if (text.isEmpty) return;

//       setState(() {
//         _recognizedText += " $text";
//         _intermediateResult = '';
//       });
//     });
//     _azureSpeechRecognition.onExceptionHandler(
//         (exception) => debugPrint("Speech recognition exception: $exception"));
//     _azureSpeechRecognition.setRecognitionStartedHandler(
//         () => debugPrint("Speech recognition has started."));
//     _azureSpeechRecognition.setRecognitionStoppedHandler(
//         () => debugPrint("Speech recognition has stopped."));
//     _azureSpeechRecognition.setRecognitionResultHandler((text) {
//       setState(() {
//         _intermediateResult = text;
//       });
//     });
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: Text('Continuous Recognition'),
//       ),
//       body: Column(
//         children: [
//           SizedBox(height: 20),
//           GestureDetector(
//             onTap: () {
//               setState(() {
//                 _isMicOn = !_isMicOn;
//               });
//               AzureSpeechRecognition.continuousRecording();
//             },
//             child: Container(
//               width: 80,
//               height: 80,
//               decoration: BoxDecoration(
//                 shape: BoxShape.circle,
//                 color: _isMicOn ? Colors.green : Colors.red,
//               ),
//               child: Icon(
//                 _isMicOn ? Icons.mic : Icons.mic_off,
//                 color: Colors.white,
//                 size: 40,
//               ),
//             ),
//           ),
//           SizedBox(height: 20),
//           Text('Recognizing: $_intermediateResult'),
//           SizedBox(height: 20),
//           Expanded(
//             child: TextField(
//               readOnly: true,
//               maxLines: null,
//               decoration: InputDecoration(
//                 border: OutlineInputBorder(),
//                 labelText: 'Transcription',
//               ),
//               controller: TextEditingController(text: _recognizedText),
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }

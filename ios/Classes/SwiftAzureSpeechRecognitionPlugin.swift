import Flutter
import UIKit
import MicrosoftCognitiveServicesSpeech
import AVFoundation

@available(iOS 13.0, *)
struct SimpleRecognitionTask {
    var task: Task<Void, Never>
    var isCanceled: Bool
}

@available(iOS 13.0, *)
public class SwiftAzureSpeechRecognitionPlugin: NSObject, FlutterPlugin {
    var azureChannel: FlutterMethodChannel
    var continousListeningStarted: Bool = false
    var continousSpeechRecognizer: SPXSpeechRecognizer? = nil
    var simpleRecognitionTasks: Dictionary<String, SimpleRecognitionTask> = [:]
    var transcriber: SPXConversationTranscriber? = nil
    var audioConfig: SPXAudioConfiguration? = nil
    var speechConfig: SPXSpeechConfiguration? = nil;
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "azure_speech_recognition", binaryMessenger: registrar.messenger())
        let instance: SwiftAzureSpeechRecognitionPlugin = SwiftAzureSpeechRecognitionPlugin(azureChannel: channel)
        registrar.addMethodCallDelegate(instance, channel: channel)
    }
    init(azureChannel: FlutterMethodChannel) {
        self.azureChannel = azureChannel
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? Dictionary<String, Any>
        let speechSubscriptionKey = args?["subscriptionKey"] as? String ?? ""
        let serviceRegion = args?["region"] as? String ?? ""
        let lang = args?["language"] as? String ?? ""
        let timeoutMs = args?["timeout"] as? String ?? ""
        let referenceText = args?["referenceText"] as? String ?? ""
        let phonemeAlphabet = args?["phonemeAlphabet"] as? String ?? "IPA"
        let granularityString = args?["granularity"] as? String ?? "phoneme"
        let enableMiscue = args?["enableMiscue"] as? Bool ?? false
        let nBestPhonemeCount = args?["nBestPhonemeCount"] as? Int
        var granularity: SPXPronunciationAssessmentGranularity
        if (granularityString == "text") {
            granularity = SPXPronunciationAssessmentGranularity.fullText
        }
        else if (granularityString == "word") {
            granularity = SPXPronunciationAssessmentGranularity.word
        }
        else {
            granularity = SPXPronunciationAssessmentGranularity.phoneme
        }
        if (call.method == "simpleVoice") {
            print("Called simpleVoice")
            simpleSpeechRecognition(speechSubscriptionKey: speechSubscriptionKey, serviceRegion: serviceRegion, lang: lang, timeoutMs: timeoutMs)
            result(true)
        }
        else if (call.method == "simpleVoiceWithAssessment") {
            print("Called simpleVoiceWithAssessment")
            simpleSpeechRecognitionWithAssessment(referenceText: referenceText, phonemeAlphabet: phonemeAlphabet,  granularity: granularity, enableMiscue: enableMiscue, speechSubscriptionKey: speechSubscriptionKey, serviceRegion: serviceRegion, lang: lang, timeoutMs: timeoutMs, nBestPhonemeCount: nBestPhonemeCount)
            result(true)
        }
        else if (call.method == "isContinuousRecognitionOn") {
            print("Called isContinuousRecognitionOn: \(continousListeningStarted)")
            result(continousListeningStarted)
        }
        else if (call.method == "continuousStream") {
            print("Called continuousStream")
            continuousStream(speechSubscriptionKey: speechSubscriptionKey, serviceRegion: serviceRegion, lang: lang)
            result(true)
        }
        else if (call.method == "continuousStreamWithAssessment") {
            print("Called continuousStreamWithAssessment")
            continuousStreamWithAssessment(referenceText: referenceText, phonemeAlphabet: phonemeAlphabet,  granularity: granularity, enableMiscue: enableMiscue, speechSubscriptionKey: speechSubscriptionKey, serviceRegion: serviceRegion, lang: lang, nBestPhonemeCount: nBestPhonemeCount)
            result(true)
        }
        else if (call.method == "stopContinuousStream") {
            stopContinuousStream(flutterResult: result)
        }
        else {
            result(FlutterMethodNotImplemented)
        }
    }
    
    
    
    private func cancelActiveSimpleRecognitionTasks() {
        print("Cancelling any active tasks")
        for taskId in simpleRecognitionTasks.keys {
            print("Cancelling task \(taskId)")
            simpleRecognitionTasks[taskId]?.task.cancel()
            simpleRecognitionTasks[taskId]?.isCanceled = true
        }
    }
    
    private func simpleSpeechRecognition(speechSubscriptionKey : String, serviceRegion : String, lang: String, timeoutMs: String) {
        print("Created new recognition task")
        cancelActiveSimpleRecognitionTasks()
        let taskId = UUID().uuidString;
        let task = Task {
            print("Started recognition with task ID \(taskId)")
            var speechConfig: SPXSpeechConfiguration?
            do {
                let audioSession = AVAudioSession.sharedInstance()
                // Request access to the microphone
                try audioSession.setCategory(AVAudioSession.Category.record, mode: AVAudioSession.Mode.default, options: AVAudioSession.CategoryOptions.allowBluetooth)
                try audioSession.setActive(true)
                print("Setting custom audio session")
                // Initialize speech recognizer and specify correct subscription key and service region
                try speechConfig = SPXSpeechConfiguration(subscription: speechSubscriptionKey, region: serviceRegion)
            } catch {
                print("error \(error) happened")
                speechConfig = nil
            }
            speechConfig?.speechRecognitionLanguage = lang
            speechConfig?.setPropertyTo(timeoutMs, by: SPXPropertyId.speechSegmentationSilenceTimeoutMs)
            
            let audioConfig = SPXAudioConfiguration()
            let reco = try! SPXSpeechRecognizer(speechConfiguration: speechConfig!, audioConfiguration: audioConfig)
            
            reco.addRecognizingEventHandler() {reco, evt in
                if (self.simpleRecognitionTasks[taskId]?.isCanceled ?? false) { // Discard intermediate results if the task was cancelled
                    print("Ignoring partial result. TaskID: \(taskId)")
                }
                else {
                    print("Intermediate result: \(evt.result.text ?? "(no result)")\nTaskID: \(taskId)")
                    self.azureChannel.invokeMethod("speech.onSpeech", arguments: evt.result.text)
                }
            }
            
            let result = try! reco.recognizeOnce()
            if (Task.isCancelled) {
                print("Ignoring final result. TaskID: \(taskId)")
            } else {
                print("Final result: \(result.text ?? "(no result)")\nReason: \(result.reason.rawValue)\nTaskID: \(taskId)")
                if result.reason != SPXResultReason.recognizedSpeech {
                    let cancellationDetails = try! SPXCancellationDetails(fromCanceledRecognitionResult: result)
                    print("Cancelled: \(cancellationDetails.description), \(cancellationDetails.errorDetails)\nTaskID: \(taskId)")
                    print("Did you set the speech resource key and region values?")
                    self.azureChannel.invokeMethod("speech.onFinalResponse", arguments: "")
                }
                else {
                    self.azureChannel.invokeMethod("speech.onFinalResponse", arguments: result.text)
                }
                
            }
            self.simpleRecognitionTasks.removeValue(forKey: taskId)
        }
        simpleRecognitionTasks[taskId] = SimpleRecognitionTask(task: task, isCanceled: false)
    }
    
    private func simpleSpeechRecognitionWithAssessment(referenceText: String, phonemeAlphabet: String, granularity: SPXPronunciationAssessmentGranularity, enableMiscue: Bool, speechSubscriptionKey : String, serviceRegion : String, lang: String, timeoutMs: String, nBestPhonemeCount: Int?) {
        print("Created new recognition task")
        cancelActiveSimpleRecognitionTasks()
        let taskId = UUID().uuidString;
        let task = Task {
            print("Started recognition with task ID \(taskId)")
            var speechConfig: SPXSpeechConfiguration?
            var pronunciationAssessmentConfig: SPXPronunciationAssessmentConfiguration?
            do {
                let audioSession = AVAudioSession.sharedInstance()
                // Request access to the microphone
                try audioSession.setCategory(AVAudioSession.Category.record, mode: AVAudioSession.Mode.default, options: AVAudioSession.CategoryOptions.allowBluetooth)
                try audioSession.setActive(true)
                print("Setting custom audio session")
                // Initialize speech recognizer and specify correct subscription key and service region
                try speechConfig = SPXSpeechConfiguration(subscription: speechSubscriptionKey, region: serviceRegion)
                try pronunciationAssessmentConfig = SPXPronunciationAssessmentConfiguration.init(
                    referenceText,
                    gradingSystem: SPXPronunciationAssessmentGradingSystem.hundredMark,
                    granularity: granularity,
                    enableMiscue: enableMiscue)
            } catch {
                print("error \(error) happened")
                speechConfig = nil
            }
            pronunciationAssessmentConfig?.phonemeAlphabet = phonemeAlphabet
            
            if nBestPhonemeCount != nil {
                pronunciationAssessmentConfig?.nbestPhonemeCount = nBestPhonemeCount!
            }
            
            speechConfig?.speechRecognitionLanguage = lang
            speechConfig?.setPropertyTo(timeoutMs, by: SPXPropertyId.speechSegmentationSilenceTimeoutMs)
            
            let audioConfig = SPXAudioConfiguration()
            let reco = try! SPXSpeechRecognizer(speechConfiguration: speechConfig!, audioConfiguration: audioConfig)
            try! pronunciationAssessmentConfig?.apply(to: reco)
            
            reco.addRecognizingEventHandler() {reco, evt in
                if (self.simpleRecognitionTasks[taskId]?.isCanceled ?? false) { // Discard intermediate results if the task was cancelled
                    print("Ignoring partial result. TaskID: \(taskId)")
                }
                else {
                    print("Intermediate result: \(evt.result.text ?? "(no result)")\nTaskID: \(taskId)")
                    self.azureChannel.invokeMethod("speech.onSpeech", arguments: evt.result.text)
                }
            }
            
            let result = try! reco.recognizeOnce()
            if (Task.isCancelled) {
                print("Ignoring final result. TaskID: \(taskId)")
            } else {
                print("Final result: \(result.text ?? "(no result)")\nReason: \(result.reason.rawValue)\nTaskID: \(taskId)")
                let pronunciationAssessmentResultJson = result.properties?.getPropertyBy(SPXPropertyId.speechServiceResponseJsonResult)
                print("pronunciationAssessmentResultJson: \(pronunciationAssessmentResultJson ?? "(no result)")")
                if result.reason != SPXResultReason.recognizedSpeech {
                    let cancellationDetails = try! SPXCancellationDetails(fromCanceledRecognitionResult: result)
                    print("Cancelled: \(cancellationDetails.description), \(cancellationDetails.errorDetails)\nTaskID: \(taskId)")
                    print("Did you set the speech resource key and region values?")
                    self.azureChannel.invokeMethod("speech.onFinalResponse", arguments: "")
                    self.azureChannel.invokeMethod("speech.onAssessmentResult", arguments: "")
                }
                else {
                    self.azureChannel.invokeMethod("speech.onFinalResponse", arguments: result.text)
                    self.azureChannel.invokeMethod("speech.onAssessmentResult", arguments: pronunciationAssessmentResultJson)
                }
                
            }
            self.simpleRecognitionTasks.removeValue(forKey: taskId)
        }
        simpleRecognitionTasks[taskId] = SimpleRecognitionTask(task: task, isCanceled: false)
    }
    
    private func stopContinuousStream(flutterResult: FlutterResult) {
        if (continousListeningStarted) {
            print("Stopping continous recognition")
            do {
                try continousSpeechRecognizer!.stopContinuousRecognition()
                self.azureChannel.invokeMethod("speech.onRecognitionStopped", arguments: nil)
                continousSpeechRecognizer = nil
                continousListeningStarted = false
                flutterResult(true)
            }
            catch {
                print("Error occurred stopping continous recognition")
            }
        }
    }
    
    // private func continuousStream(speechSubscriptionKey : String, serviceRegion : String, lang: String) {
    //     if (continousListeningStarted) {
    //         print("Stopping continous recognition")
    //         do {
    //             try continousSpeechRecognizer!.stopContinuousRecognition()
    //             self.azureChannel.invokeMethod("speech.onRecognitionStopped", arguments: nil)
    //             continousSpeechRecognizer = nil
    //             continousListeningStarted = false
    //         }
    //         catch {
    //             print("Error occurred stopping continous recognition")
    //         }
    //     }
    //     else {
    //         print("Starting continous recognition")
    //         do {
    //             let audioSession = AVAudioSession.sharedInstance()
    //             // Request access to the microphone
    //             try audioSession.setCategory(AVAudioSession.Category.record, mode: AVAudioSession.Mode.default, options: AVAudioSession.CategoryOptions.allowBluetooth)
    //             try audioSession.setActive(true)
    //             print("Setting custom audio session")
    //         }
    //         catch {
    //             print("An unexpected error occurred")
    //         }
            
    //         let speechConfig = try! SPXSpeechConfiguration(subscription: speechSubscriptionKey, region: serviceRegion)
            
    //         speechConfig.speechRecognitionLanguage = lang
            
    //         let audioConfig = SPXAudioConfiguration()
            
    //         continousSpeechRecognizer = try! SPXSpeechRecognizer(speechConfiguration: speechConfig, audioConfiguration: audioConfig)
    //         continousSpeechRecognizer!.addRecognizingEventHandler() {reco, evt in
    //             print("intermediate recognition result: \(evt.result.text ?? "(no result)")")
    //             self.azureChannel.invokeMethod("speech.onSpeech", arguments: evt.result.text)
    //         }
    //         continousSpeechRecognizer!.addRecognizedEventHandler({reco, evt in
    //             let res = evt.result.text
    //             print("final result \(res!)")
    //             self.azureChannel.invokeMethod("speech.onFinalResponse", arguments: res)
    //         })

    //         let transcriber = try! SPXConversationTranscriber(speechConfiguration: speechConfig, audioConfiguration: audioConfig)

    //         transcriber.addTranscribedEventHandler({reco, evt in
    //             let result = evt.result
    //             print("final transcription result: \(result?.text ?? "(no result)") speakerid: \(result?.speakerId ?? "(no result)")")
    //             // self.azureChannel.invokeMethod("speech.onFinalResponseWithSpeaker", arguments: "final transcription result: \(result?.text ?? "(no result)") speakerid: \(result?.speakerId ?? "(no result)")")
    //             self.azureChannel.invokeMethod("speech.onFinalResponseWithSpeaker", arguments: [
    //                 "text": result?.text ?? "(no result)",
    //                 "speakerId": result?.speakerId ?? "(no result)"
    //             ])
    //             // self.updateLabel(text: (evt.result?.text)! + "\nspeakerId:" + (evt.result?.speakerId)!, color: .gray)
    //         })

    //         print("Listening...")
    //         try! continousSpeechRecognizer!.startContinuousRecognition()
    //         self.azureChannel.invokeMethod("speech.onRecognitionStarted", arguments: nil)
    //         continousListeningStarted = true
    //     }
    // }

    private func continuousStream(speechSubscriptionKey: String, serviceRegion: String, lang: String) {
        if (continousListeningStarted) {
            print("Stopping continuous transcription")
            do {
                try transcriber?.stopTranscribingAsync({ _, _ in })
                self.azureChannel.invokeMethod("speech.onRecognitionStopped", arguments: nil)
                transcriber = nil
                continousListeningStarted = false
            } catch {
                print("Error occurred stopping continuous transcription")
            }
        } else {
            print("Starting continuous transcription")
            do {
                let audioSession = AVAudioSession.sharedInstance()
                try audioSession.setCategory(.record, mode: .default, options: [.allowBluetooth])
                try audioSession.setActive(true)
            } catch {
                print("Failed to setup AVAudioSession: \(error)")
            }

//             let speechConfig = try! SPXSpeechConfiguration(subscription: speechSubscriptionKey, region: serviceRegion)
            let speechConfig = try! SPXSpeechConfiguration(endpoint: serviceRegion, subscription: speechSubscriptionKey)
            speechConfig.speechRecognitionLanguage = lang

            let audioConfig = SPXAudioConfiguration() // default mic input
            transcriber = try! SPXConversationTranscriber(speechConfiguration: speechConfig, audioConfiguration: audioConfig)

            transcriber?.addTranscribingEventHandler { _, evt in
                let text = evt.result?.text ?? "(no result)"
                let speaker = evt.result?.speakerId ?? "(unknown)"
                print("intermediate transcription: \(text) [\(speaker)]")
                let payload = ["text": text, "speaker": speaker]
                self.azureChannel.invokeMethod("speech.onSpeech", arguments: "intermediate transcription: \(text) [\(speaker)]")
            }

            transcriber?.addTranscribedEventHandler { _, evt in
                let text = evt.result?.text ?? "(no result)"
                let speaker = evt.result?.speakerId ?? "(unknown)"
                let duration = evt.result?.duration ?? 0
                let offset = evt.result?.offset ?? 0

                let ticksToSeconds = 1.0 / 10_000_000.0
                let startSeconds = Double(offset) * ticksToSeconds
                let durationSeconds = Double(duration) * ticksToSeconds
                let endSeconds = startSeconds + durationSeconds

                func formatTime(_ seconds: Double) -> String {
                    let minutes = Int(seconds) / 60
                    let secs = Int(seconds) % 60
                    return String(format: "%02d:%02d", minutes, secs)
                }

//                 let timeRange = "[\(formatTime(startSeconds)) - \(formatTime(endSeconds))]"
                let timeRange = "[\(formatTime(endSeconds)) - \(formatTime(startSeconds))]"

                print("final transcription: \(text) [\(speaker)]")

                //let payload = ["text": text, "speaker": speaker]
                self.azureChannel.invokeMethod("speech.onFinalResponse", arguments: "[\(speaker)]:::\(text):::\(duration):::\(offset):::\(timeRange)")
            }

            transcriber?.addSessionStartedEventHandler { _, _ in
                print("session started")
                self.azureChannel.invokeMethod("speech.onRecognitionStarted", arguments: nil)
            }

            transcriber?.addSessionStoppedEventHandler { _, _ in
                print("session stopped")
                self.azureChannel.invokeMethod("speech.onRecognitionStopped", arguments: nil)
            }

            transcriber?.addCanceledEventHandler { _, evt in
                print("transcription canceled: \(evt.errorDetails ?? "unknown error")")
            }

            try! transcriber?.startTranscribingAsync({ _, error in
                if let error = error {
                    print("Failed to start transcription: \(error.localizedDescription)")
                } else {
                    print("Transcribing started")
                }
            })

            continousListeningStarted = true
        }
    }

    
    private func continuousStreamWithAssessment(referenceText: String, phonemeAlphabet: String, granularity: SPXPronunciationAssessmentGranularity, enableMiscue: Bool, speechSubscriptionKey : String, serviceRegion : String, lang: String, nBestPhonemeCount: Int?) {
        print("Continuous recognition started: \(continousListeningStarted)")
        if (continousListeningStarted) {
            print("Stopping continous recognition")
            do {
                try continousSpeechRecognizer!.stopContinuousRecognition()
                self.azureChannel.invokeMethod("speech.onRecognitionStopped", arguments: nil)
                continousSpeechRecognizer = nil
                continousListeningStarted = false
            }
            catch {
                print("Error occurred stopping continous recognition")
            }
        }
        else {
            print("Starting continous recognition")
            do {
                let audioSession = AVAudioSession.sharedInstance()
                // Request access to the microphone
                try audioSession.setCategory(AVAudioSession.Category.record, mode: AVAudioSession.Mode.default, options: AVAudioSession.CategoryOptions.allowBluetooth)
                try audioSession.setActive(true)
                print("Setting custom audio session")
                
                let speechConfig = try SPXSpeechConfiguration(subscription: speechSubscriptionKey, region: serviceRegion)
                
                speechConfig.speechRecognitionLanguage = lang
                
                let pronunciationAssessmentConfig = try SPXPronunciationAssessmentConfiguration.init(
                    referenceText,
                    gradingSystem: SPXPronunciationAssessmentGradingSystem.hundredMark,
                    granularity: granularity,
                    enableMiscue: enableMiscue)
                pronunciationAssessmentConfig.phonemeAlphabet = phonemeAlphabet
                
                if nBestPhonemeCount != nil {
                    pronunciationAssessmentConfig.nbestPhonemeCount = nBestPhonemeCount!
                }
                
                
                let audioConfig = SPXAudioConfiguration()
                
                continousSpeechRecognizer = try SPXSpeechRecognizer(speechConfiguration: speechConfig, audioConfiguration: audioConfig)
                try pronunciationAssessmentConfig.apply(to: continousSpeechRecognizer!)
                
                continousSpeechRecognizer!.addRecognizingEventHandler() {reco, evt in
                    print("intermediate recognition result: \(evt.result.text ?? "(no result)")")
                    self.azureChannel.invokeMethod("speech.onSpeech", arguments: evt.result.text)
                }
                continousSpeechRecognizer!.addRecognizedEventHandler({reco, evt in
                    let result = evt.result
                    print("Final result: \(result.text ?? "(no result)")\nReason: \(result.reason.rawValue)")
                    let pronunciationAssessmentResultJson = result.properties?.getPropertyBy(SPXPropertyId.speechServiceResponseJsonResult)
                    print("pronunciationAssessmentResultJson: \(pronunciationAssessmentResultJson ?? "(no result)")")
                    self.azureChannel.invokeMethod("speech.onFinalResponse", arguments: result.text)
                    self.azureChannel.invokeMethod("speech.onAssessmentResult", arguments: pronunciationAssessmentResultJson)
                })

                let transcriber = try! SPXConversationTranscriber(speechConfiguration: speechConfig, audioConfiguration: audioConfig)

                transcriber.addTranscribedEventHandler({reco, evt in
                    let result = evt.result
                    print("final transcription result: \(result?.text ?? "(no result)") speakerid: \(result?.speakerId ?? "(no result)")")
                    self.azureChannel.invokeMethod("speech.onFinalResponseWithSpeaker", arguments: "final transcription result: \(result?.text ?? "(no result)") speakerid: \(result?.speakerId ?? "(no result)")")
                    // self.updateLabel(text: (evt.result?.text)! + "\nspeakerId:" + (evt.result?.speakerId)!, color: .gray)
                })

                print("Listening...")
                try continousSpeechRecognizer!.startContinuousRecognition()
                self.azureChannel.invokeMethod("speech.onRecognitionStarted", arguments: nil)
                continousListeningStarted = true
            }
            catch {
                print("An unexpected error occurred: \(error)")
            }
        }
    }
}

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
    
    // NEW: conversation transcriber for speaker ID
    var conversationTranscriber: SPXConversationTranscriber? = nil
    
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
            simpleSpeechRecognition(speechSubscriptionKey: speechSubscriptionKey, serviceRegion: serviceRegion, lang: lang, timeoutMs: timeoutMs)
            result(true)
        }
        else if (call.method == "simpleVoiceWithAssessment") {
            simpleSpeechRecognitionWithAssessment(referenceText: referenceText, phonemeAlphabet: phonemeAlphabet, granularity: granularity, enableMiscue: enableMiscue, speechSubscriptionKey: speechSubscriptionKey, serviceRegion: serviceRegion, lang: lang, timeoutMs: timeoutMs, nBestPhonemeCount: nBestPhonemeCount)
            result(true)
        }
        else if (call.method == "isContinuousRecognitionOn") {
            result(continousListeningStarted)
        }
        else if (call.method == "continuousStream") {
            continuousStream(speechSubscriptionKey: speechSubscriptionKey, serviceRegion: serviceRegion, lang: lang)
            result(true)
        }
        else if (call.method == "continuousStreamWithAssessment") {
            continuousStreamWithAssessment(referenceText: referenceText, phonemeAlphabet: phonemeAlphabet, granularity: granularity, enableMiscue: enableMiscue, speechSubscriptionKey: speechSubscriptionKey, serviceRegion: serviceRegion, lang: lang, nBestPhonemeCount: nBestPhonemeCount)
            result(true)
        }
        else if (call.method == "stopContinuousStream") {
            stopContinuousStream(flutterResult: result)
        }
        // === NEW METHODS FOR SPEAKER ID TRANSCRIPTION ===
        else if (call.method == "startConversationTranscription") {
            startConversationTranscription(speechSubscriptionKey: speechSubscriptionKey, serviceRegion: serviceRegion, lang: lang)
            result(true)
        }
        else if (call.method == "stopConversationTranscription") {
            stopConversationTranscription(result: result)
        }
        else {
            result(FlutterMethodNotImplemented)
        }
    }
    
    // Existing simple recognition implementations unchanged...
    private func cancelActiveSimpleRecognitionTasks() {
        for taskId in simpleRecognitionTasks.keys {
            simpleRecognitionTasks[taskId]?.task.cancel()
            simpleRecognitionTasks[taskId]?.isCanceled = true
        }
    }
    
    private func simpleSpeechRecognition(speechSubscriptionKey : String, serviceRegion : String, lang: String, timeoutMs: String) {
        cancelActiveSimpleRecognitionTasks()
        let taskId = UUID().uuidString
        let task = Task {
            var speechConfig: SPXSpeechConfiguration?
            do {
                let audioSession = AVAudioSession.sharedInstance()
                try audioSession.setCategory(.record, mode: .default, options: .allowBluetooth)
                try audioSession.setActive(true)
                speechConfig = try SPXSpeechConfiguration(subscription: speechSubscriptionKey, region: serviceRegion)
            } catch {
                speechConfig = nil
            }
            speechConfig?.speechRecognitionLanguage = lang
            speechConfig?.setPropertyTo(timeoutMs, by: SPXPropertyId.speechSegmentationSilenceTimeoutMs)
            
            let audioConfig = SPXAudioConfiguration()
            let reco = try! SPXSpeechRecognizer(speechConfiguration: speechConfig!, audioConfiguration: audioConfig)
            
            reco.addRecognizingEventHandler() { reco, evt in
                if self.simpleRecognitionTasks[taskId]?.isCanceled ?? false {
                    // discard
                }
                else {
                    self.azureChannel.invokeMethod("speech.onSpeech", arguments: evt.result.text)
                }
            }
            
            let result = try! reco.recognizeOnce()
            if Task.isCancelled {
                // discard
            } else {
                if result.reason != SPXResultReason.recognizedSpeech {
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
        cancelActiveSimpleRecognitionTasks()
        let taskId = UUID().uuidString
        let task = Task {
            var speechConfig: SPXSpeechConfiguration?
            var pronunciationAssessmentConfig: SPXPronunciationAssessmentConfiguration?
            do {
                let audioSession = AVAudioSession.sharedInstance()
                try audioSession.setCategory(.record, mode: .default, options: .allowBluetooth)
                try audioSession.setActive(true)
                speechConfig = try SPXSpeechConfiguration(subscription: speechSubscriptionKey, region: serviceRegion)
                pronunciationAssessmentConfig = try SPXPronunciationAssessmentConfiguration(referenceText, gradingSystem: .hundredMark, granularity: granularity, enableMiscue: enableMiscue)
            } catch {
                speechConfig = nil
            }
            pronunciationAssessmentConfig?.phonemeAlphabet = phonemeAlphabet
            if let count = nBestPhonemeCount {
                pronunciationAssessmentConfig?.nbestPhonemeCount = count
            }
            speechConfig?.speechRecognitionLanguage = lang
            speechConfig?.setPropertyTo(timeoutMs, by: SPXPropertyId.speechSegmentationSilenceTimeoutMs)
            
            let audioConfig = SPXAudioConfiguration()
            let reco = try! SPXSpeechRecognizer(speechConfiguration: speechConfig!, audioConfiguration: audioConfig)
            try! pronunciationAssessmentConfig?.apply(to: reco)
            
            reco.addRecognizingEventHandler() { reco, evt in
                if self.simpleRecognitionTasks[taskId]?.isCanceled ?? false {
                    // discard
                }
                else {
                    self.azureChannel.invokeMethod("speech.onSpeech", arguments: evt.result.text)
                }
            }
            
            let result = try! reco.recognizeOnce()
            if Task.isCancelled {
                // discard
            } else {
                let jsonResult = result.properties?.getPropertyBy(SPXPropertyId.speechServiceResponseJsonResult)
                if result.reason != SPXResultReason.recognizedSpeech {
                    self.azureChannel.invokeMethod("speech.onFinalResponse", arguments: "")
                    self.azureChannel.invokeMethod("speech.onAssessmentResult", arguments: "")
                }
                else {
                    self.azureChannel.invokeMethod("speech.onFinalResponse", arguments: result.text)
                    self.azureChannel.invokeMethod("speech.onAssessmentResult", arguments: jsonResult)
                }
            }
            self.simpleRecognitionTasks.removeValue(forKey: taskId)
        }
        simpleRecognitionTasks[taskId] = SimpleRecognitionTask(task: task, isCanceled: false)
    }
    
    private func stopContinuousStream(flutterResult: FlutterResult) {
        if continousListeningStarted {
            do {
                try continousSpeechRecognizer?.stopContinuousRecognition()
                self.azureChannel.invokeMethod("speech.onRecognitionStopped", arguments: nil)
                continousSpeechRecognizer = nil
                continousListeningStarted = false
                flutterResult(true)
            } catch {
                flutterResult(false)
            }
        } else {
            flutterResult(false)
        }
    }
    
    private func continuousStream(speechSubscriptionKey : String, serviceRegion : String, lang: String) {
        if continousListeningStarted {
            do {
                try continousSpeechRecognizer?.stopContinuousRecognition()
                self.azureChannel.invokeMethod("speech.onRecognitionStopped", arguments: nil)
                continousSpeechRecognizer = nil
                continousListeningStarted = false
            } catch { }
        } else {
            do {
                let audioSession = AVAudioSession.sharedInstance()
                try audioSession.setCategory(.record, mode: .default, options: .allowBluetooth)
                try audioSession.setActive(true)
            } catch { }
            
            let speechConfig = try! SPXSpeechConfiguration(subscription: speechSubscriptionKey, region: serviceRegion)
            speechConfig.speechRecognitionLanguage = lang
            
            let audioConfig = SPXAudioConfiguration()
            
            continousSpeechRecognizer = try! SPXSpeechRecognizer(speechConfiguration: speechConfig, audioConfiguration: audioConfig)
            continousSpeechRecognizer!.addRecognizingEventHandler() { reco, evt in
                self.azureChannel.invokeMethod("speech.onSpeech", arguments: evt.result.text)
            }
            continousSpeechRecognizer!.addRecognizedEventHandler() { reco, evt in
                self.azureChannel.invokeMethod("speech.onFinalResponse", arguments: evt.result.text)
            }
            
            try! continousSpeechRecognizer!.startContinuousRecognition()
            self.azureChannel.invokeMethod("speech.onRecognitionStarted", arguments: nil)
            continousListeningStarted = true
        }
    }
    
    private func continuousStreamWithAssessment(referenceText: String, phonemeAlphabet: String, granularity: SPXPronunciationAssessmentGranularity, enableMiscue: Bool, speechSubscriptionKey : String, serviceRegion : String, lang: String, nBestPhonemeCount: Int?) {
        if continousListeningStarted {
            do {
                try continousSpeechRecognizer?.stopContinuousRecognition()
                self.azureChannel.invokeMethod("speech.onRecognitionStopped", arguments: nil)
                continousSpeechRecognizer = nil
                continousListeningStarted = false
            } catch { }
        } else {
            do {
                let audioSession = AVAudioSession.sharedInstance()
                try audioSession.setCategory(.record, mode: .default, options: .allowBluetooth)
                try audioSession.setActive(true)
                
                let speechConfig = try SPXSpeechConfiguration(subscription: speechSubscriptionKey, region: serviceRegion)
                speechConfig.speechRecognitionLanguage = lang
                
                let pronunciationAssessmentConfig = try SPXPronunciationAssessmentConfiguration(referenceText, gradingSystem: .hundredMark, granularity: granularity, enableMiscue: enableMiscue)
                pronunciationAssessmentConfig.phonemeAlphabet = phonemeAlphabet
                if let count = nBestPhonemeCount {
                    pronunciationAssessmentConfig.nbestPhonemeCount = count
                }
                
                let audioConfig = SPXAudioConfiguration()
                
                continousSpeechRecognizer = try SPXSpeechRecognizer(speechConfiguration: speechConfig, audioConfiguration: audioConfig)
                try pronunciationAssessmentConfig.apply(to: continousSpeechRecognizer!)
                
                continousSpeechRecognizer!.addRecognizingEventHandler() { reco, evt in
                    self.azureChannel.invokeMethod("speech.onSpeech", arguments: evt.result.text)
                }
                continousSpeechRecognizer!.addRecognizedEventHandler() { reco, evt in
                    let result = evt.result
                    let jsonResult = result.properties?.getPropertyBy(SPXPropertyId.speechServiceResponseJsonResult)
                    self.azureChannel.invokeMethod("speech.onFinalResponse", arguments: result.text)
                    self.azureChannel.invokeMethod("speech.onAssessmentResult", arguments: jsonResult)
                }
                
                try continousSpeechRecognizer!.startContinuousRecognition()
                self.azureChannel.invokeMethod("speech.onRecognitionStarted", arguments: nil)
                continousListeningStarted = true
            } catch {
                print("Error in continuousStreamWithAssessment: \(error)")
            }
        }
    }
    
    // === NEW: start conversation transcription with speaker ID ===
    private func startConversationTranscription(speechSubscriptionKey: String, serviceRegion: String, lang: String) {
        do {
            let speechConfig = try SPXSpeechConfiguration(subscription: speechSubscriptionKey, region: serviceRegion)
            speechConfig.speechRecognitionLanguage = lang
            
            let audioConfig = SPXAudioConfiguration()
            
            conversationTranscriber = try SPXConversationTranscriber(speechConfiguration: speechConfig, audioConfiguration: audioConfig)
            
            conversationTranscriber!.addTranscribedEventHandler() { [weak self] _, evt in
                guard let self = self else { return }
                let text = evt.result?.text ?? "(no result)"
                let speakerId = evt.result?.speakerId ?? "(no speaker ID)"
                
                let args: [String: String] = ["text": text, "speakerId": speakerId]
                self.azureChannel.invokeMethod("speech.onTranscribedWithSpeaker", arguments: args)
            }
            
            conversationTranscriber!.addSessionStartedEventHandler() { [weak self] _, _ in
                self?.azureChannel.invokeMethod("speech.onRecognitionStarted", arguments: nil)
            }
            
            conversationTranscriber!.addSessionStoppedEventHandler() { [weak self] _, _ in
                self?.azureChannel.invokeMethod("speech.onRecognitionStopped", arguments: nil)
                self?.conversationTranscriber = nil
            }
            
            conversationTranscriber!.addCanceledEventHandler() { [weak self] _, evt in
                self?.azureChannel.invokeMethod("speech.onRecognitionCanceled", arguments: evt.errorDetails)
                self?.conversationTranscriber = nil
            }
            
            try conversationTranscriber?.startTranscribingAsync({ started, error in
                if let error = error {
                    self.azureChannel.invokeMethod("speech.onError", arguments: error.localizedDescription)
                }
            })
        } catch {
            self.azureChannel.invokeMethod("speech.onError", arguments: error.localizedDescription)
        }
    }
    
    // === NEW: stop conversation transcription ===
    private func stopConversationTranscription(result: @escaping FlutterResult) {
        guard let transcriber = conversationTranscriber else {
            result(false)
            return
        }
        do {
            try transcriber.stopTranscribingAsync({ stopped, error in
                if let error = error {
                    self.azureChannel.invokeMethod("speech.onError", arguments: error.localizedDescription)
                    result(false)
                } else {
                    self.azureChannel.invokeMethod("speech.onRecognitionStopped", arguments: nil)
                    self.conversationTranscriber = nil
                    result(true)
                }
            })
        } catch {
            result(false)
        }
    }
}

import Flutter
import UIKit
import MicrosoftCognitiveServicesSpeech
import AVFoundation

@available(iOS 13.0, *)
public class SwiftAzureSpeechRecognitionPlugin: NSObject, FlutterPlugin {
    var methodChannel: FlutterMethodChannel
    var transcriber: SPXConversationTranscriber? = nil
    var audioConfig: SPXAudioConfiguration? = nil
    var speechConfig: SPXSpeechConfiguration? = nil
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "azure_speech_recognition", binaryMessenger: registrar.messenger())
        let instance = SwiftAzureSpeechRecognitionPlugin(channel: channel)
        registrar.addMethodCallDelegate(instance, channel: channel)
    }
    
    init(channel: FlutterMethodChannel) {
        self.methodChannel = channel
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        if call.method == "startConversationTranscription" {
            guard let args = call.arguments as? [String: Any],
                  let subscriptionKey = args["subscriptionKey"] as? String,
                  let region = args["region"] as? String else {
                result(FlutterError(code: "INVALID_ARGUMENTS", message: "subscriptionKey and region required", details: nil))
                return
            }
            startConversationTranscription(subscriptionKey: subscriptionKey, region: region, flutterResult: result)
        }
        else if call.method == "stopConversationTranscription" {
            stopConversationTranscription(flutterResult: result)
        }
        else {
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func startConversationTranscription(subscriptionKey: String, region: String, flutterResult: @escaping FlutterResult) {
        do {
            speechConfig = try SPXSpeechConfiguration(subscription: subscriptionKey, region: region)
            audioConfig = SPXAudioConfiguration()
            
            transcriber = try SPXConversationTranscriber(speechConfiguration: speechConfig!, audioConfiguration: audioConfig!)
            
            transcriber!.addTranscribedEventHandler() { [weak self] _, evt in
                let text = evt.result?.text ?? ""
                let speakerId = evt.result?.speakerId ?? ""
                
                // Send both text and speakerId as a dictionary to Flutter
                let resultData: [String: String] = [
                    "text": text,
                    "speakerId": speakerId
                ]
                
                self?.methodChannel.invokeMethod("onFinalTranscriptionWithSpeaker", arguments: resultData)
            }
            
            transcriber!.addSessionStartedEventHandler() { _, _ in
                print("Conversation transcription session started")
            }
            
            transcriber!.addSessionStoppedEventHandler() { [weak self] _, _ in
                print("Conversation transcription session stopped")
                self?.transcriber = nil
            }
            
            transcriber!.addCanceledEventHandler() { [weak self] _, evt in
                print("Conversation transcription canceled: \(evt.errorDetails ?? "unknown error")")
                self?.transcriber = nil
            }
            
            try transcriber?.startTranscribingAsync({ started, error in
                if started {
                    flutterResult(true)
                } else {
                    flutterResult(FlutterError(code: "START_FAILED", message: error?.localizedDescription ?? "Failed to start transcription", details: nil))
                }
            })
            
        } catch {
            flutterResult(FlutterError(code: "CONFIG_ERROR", message: error.localizedDescription, details: nil))
        }
    }
    
    private func stopConversationTranscription(flutterResult: @escaping FlutterResult) {
        guard let transcriber = transcriber else {
            flutterResult(false)
            return
        }
        do {
            try transcriber.stopTranscribingAsync({ stopped, error in
                if stopped {
                    flutterResult(true)
                } else {
                    flutterResult(FlutterError(code: "STOP_FAILED", message: error?.localizedDescription ?? "Failed to stop transcription", details: nil))
                }
            })
        } catch {
            flutterResult(FlutterError(code: "STOP_ERROR", message: error.localizedDescription, details: nil))
        }
        self.transcriber = nil
    }
}

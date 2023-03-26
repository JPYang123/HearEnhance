//
//  ViewController.swift
//  HearEnhance
//
//  Created by Jiping Yang on 3/26/23.
//

import UIKit
import AudioKit
import AVFoundation

class ViewController: UIViewController {
    // Declare audio engine and input
    var audioEngine: AudioEngine!
    var input: AudioEngine.InputNode!
    var progressBar: UIProgressView!
    var loudnessLabel: UILabel!
    var toggleButton: UIButton!
    var isEnabled: Bool = true

    @objc func handleAudioSessionInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        switch type {
        case .began:
            // Interruption began, pause the hearing aid function if enabled
            if isEnabled {
                audioEngine.pause()
            }
        case .ended:
            guard let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else {
                return
            }
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            if options.contains(.shouldResume) {
                // Resume the hearing aid function if enabled
                if isEnabled {
                    do {
                        try audioEngine.start()
                    } catch {
                        print("Failed to start audio engine: \(error)")
                    }
                }
            }
        default:
            break
        }
    }

    func createHighPassFilteredNode(_ input: Node) -> Node {
        let highPassFilter = HighPassFilter(input)
        highPassFilter.cutoffFrequency = 0 // Adjust the cutoff frequency as needed
        return highPassFilter
    }

    func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .mixWithOthers, .allowBluetooth])
            try session.setActive(true)
        } catch {
            print("Failed to set up audio session: \(error)")
        }

        NotificationCenter.default.addObserver(self, selector: #selector(handleAudioSessionInterruption), name: AVAudioSession.interruptionNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleAudioRouteChange), name: AVAudioSession.routeChangeNotification, object: nil)
    }

    @objc func handleAudioRouteChange(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }

        if reason == .oldDeviceUnavailable, isEnabled {
            do {
                try audioEngine.start()
            } catch {
                print("Failed to start audio engine: \(error)")
            }
        }
    }


    @objc func toggleHearingAid(_ sender: UIButton) {
        isEnabled.toggle()
        if isEnabled {
            toggleButton.setTitle("Turn Off", for: .normal)
            do {
                try audioEngine.start()
            } catch {
                print("Failed to start audio engine: \(error)")
            }
        } else {
            toggleButton.setTitle("Turn On", for: .normal)
            audioEngine.stop()
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = UIColor.orange
        
        // Configure the audio session
        configureAudioSession()

        // Initialize the audio engine
        audioEngine = AudioEngine()

        // Get the audio input (microphone)
        guard let inputNode = audioEngine.input else {
            fatalError("Audio input not available")
        }
        input = inputNode

        // Apply high-pass filter to the input
        let filteredInput = createHighPassFilteredNode(input)

        // Create a mixer to amplify the input sound
        let mixer = Mixer(filteredInput)
        mixer.volume = 3.0 // Adjust the volume as needed

        // Connect the mixer to the output (AirPods)
        audioEngine.output = mixer

        // Start the audio engine
        do {
            try audioEngine.start()
        } catch {
            fatalError("Failed to start the audio engine: \(error)")
        }

        // Create and configure the progress bar
        progressBar = UIProgressView(progressViewStyle: .default)
        progressBar.frame = CGRect(x: 0, y: 0, width: view.frame.width - 40, height: 20)
        progressBar.center = CGPoint(x: view.center.x, y: view.center.y - 50)
        progressBar.progressTintColor = .blue
        view.addSubview(progressBar)

        // Create and configure the loudness label
        loudnessLabel = UILabel(frame: CGRect(x: 0, y: 0, width: 200, height: 21))
        
        // Configure the loudness label
        loudnessLabel.font = UIFont.systemFont(ofSize: 18) // Set the font size to 18

        loudnessLabel.center = CGPoint(x: view.center.x, y: view.center.y - 100)
        loudnessLabel.textAlignment = .center
        loudnessLabel.text = "Loudness: 0.00"
        view.addSubview(loudnessLabel)

        // Create and configure the on/off button
        toggleButton = UIButton(type: .system)
        toggleButton.frame = CGRect(x: 0, y: 0, width: 200, height: 40)
        
        // Configure the on/off button
        toggleButton.titleLabel?.font = UIFont.systemFont(ofSize: 24) // Set the font size to 24

        toggleButton.center = CGPoint(x: view.center.x, y: view.center.y + 50)
        toggleButton.setTitle("Turn Off", for: .normal)
        toggleButton.addTarget(self, action: #selector(toggleHearingAid), for: .touchUpInside)
        view.addSubview(toggleButton)

        // Create a tap on the mixer
        let bufferSize: UInt32 = 1_024
        let mixerNode = mixer.avAudioNode
        mixerNode.installTap(onBus: 0, bufferSize: bufferSize, format: nil) { buffer, _ in
            let pcmBuffer = buffer
            let channelData = pcmBuffer.floatChannelData!
            let numChannels = Int(pcmBuffer.format.channelCount)
            let numFrames = Int(pcmBuffer.frameLength)

            var rms: Float = 0.0
            for i in 0..<numFrames {
                for j in 0..<numChannels {
                    let sample = channelData[j][i]
                    rms += sample * sample
                }
            }
            rms = sqrtf(rms / Float(numFrames * numChannels))

            let progressBarMaxValue: Float = 0.5
            let progressBarValue = min(rms / progressBarMaxValue, 1)

            let loudnessMaxValue: Float = 0.5
            let scaledRms = min((rms / loudnessMaxValue) * 100, 100)

            DispatchQueue.main.async {
                self.progressBar.progress = progressBarValue
                self.loudnessLabel.text = String(format: "Loudness: %.2f", scaledRms)
            }
        }


    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        // Stop the audio engine when the view is going to disappear
        audioEngine.stop()
    }
    
}


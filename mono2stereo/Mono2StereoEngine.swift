//
//  Mono2StereoEngine.swift
//  mono2stereo
//
//  Created by Kunihiko Ohnaka on 2021/08/16.
//

import Foundation

import AVFoundation

func makePointer<T>(withVal val: T) -> UnsafeMutablePointer<T>  {
    let pointer = UnsafeMutablePointer<T>.allocate(capacity: 1) // Tインスタンスを一つ作成する
    pointer.initialize(to: val) // 必ず初期化する
    return UnsafeMutablePointer(pointer) // UnsafePointer<T>に変換
}

class Mono2StereoEngine {
    
    private var debug: Bool
    
    private var player : UnsafeMutablePointer<Mono2StereoPlayer>
    
    init(debug: Bool) {
        self.debug = debug
        player = makePointer(withVal: Mono2StereoPlayer())
    }
    
    var inputErrorCount: Int {
        return player.pointee.inputErrorCount
    }

    var outputErrorCount: Int {
        return player.pointee.outputErrorCount
    }

    var inputSampleTime: Float64 {
        return player.pointee.inputSampleTime
    }

    var outputSampleTime: Float64 {
        return player.pointee.outputSampleTime
    }

    var inputMaxValue: Float32 {
        return player.pointee.inputMaxValue
    }

    var outputMaxValue: Float32 {
        return player.pointee.outputMaxValue
    }

    var bufferDiff: Int {
        return player.pointee.bufferDiff
    }
    var bufferDiffAvg: Double {
            //return player.pointee.bufferDiffAvg
        return player.pointee.ringBuffer.avgBufferedSize.value
    }

    var inputTotalFrames: Int {
        return player.pointee.inputTotalFrames
    }

    var outputTotalFrames: Int {
        return player.pointee.outputTotalFrames
    }

    var inputSamplingRate: Double {
        return player.pointee.inputSamplingRate
    }

    var outputSamplingRate: Double {
        return player.pointee.outputSamplingRate
    }

    private func defaultInputDeviceId() -> AudioDeviceID {
        var defaultDevice: AudioDeviceID = kAudioObjectUnknown
        var propertySize = (UInt32)(MemoryLayout<AudioDeviceID>.size)
        var defaultDeviceProperty = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMaster)
        CheckError (AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                               &defaultDeviceProperty,
                                               0,
                                               nil,
                                               &propertySize,
                                               &defaultDevice),
                    "Couldn't get default input device")
        return defaultDevice
    }
    
    // Replace with Listings 8.4 - 8.14
    func createInputUnit(audioDeviceId: AudioDeviceID?) {
        // Generates a description that matches audio HAL
        var inputcd = AudioComponentDescription()
        inputcd.componentType = kAudioUnitType_Output
        inputcd.componentSubType = kAudioUnitSubType_HALOutput
        inputcd.componentManufacturer = kAudioUnitManufacturer_Apple
        guard let comp = AudioComponentFindNext(nil, &inputcd) else {
            print("Can't get output unit")
            exit(-1)
        }
        CheckError(AudioComponentInstanceNew(comp, &player.pointee.inputUnit),
                   "Couldn't open component for inputUnit")

        var disableFlag: UInt32 = 0
        var enableFlag: UInt32 = 1
        let outputBus: AudioUnitScope = 0
        let inputBus: AudioUnitScope = 1
        CheckError (AudioUnitSetProperty(player.pointee.inputUnit,
                                         kAudioOutputUnitProperty_EnableIO,
                                         kAudioUnitScope_Input,
                                         inputBus,
                                         &enableFlag,
                                         (UInt32)(MemoryLayout<UInt32>.size)),
                    "Couldn't enable input on I/O unit")

        CheckError (AudioUnitSetProperty(player.pointee.inputUnit,
                                         kAudioOutputUnitProperty_EnableIO,
                                         kAudioUnitScope_Output,
                                         outputBus,
                                         &disableFlag,
                                         (UInt32)(MemoryLayout<UInt32>.size)),
                    "Couldn't disable output on I/O unit")

        // この時点で、あなたはまだ要約でAUHALを扱っています。 この入力ユニットを特定の
        // オーディオデバイスに関連付けていません。リスト8.6を使用して関連付けます。
        // これは、第4章「記録」（リスト4.20および4.21を参照）で使用したAudioObjectGetPropertyData（）
        // 呼び出しを使用して、入力ハードウェアのサンプルレートを計算します。
        // この場合、必要なのは、システム環境設定で現在設定されている入力デバイスを識別するAudioDeviceIDだけです。
        
        var inputDeviceId = audioDeviceId ?? defaultInputDeviceId()

        print("Input Device: \(inputDeviceId)")
        
        CheckError(AudioUnitSetProperty(player.pointee.inputUnit,
                                        kAudioOutputUnitProperty_CurrentDevice,
                                        kAudioUnitScope_Global,
                                        outputBus,
                                        &inputDeviceId,
                                        (UInt32)(MemoryLayout<AudioDeviceID>.size)),
                   "Couldn't set default device on I/O unit")

        var propertySize = (UInt32)(MemoryLayout<AudioStreamBasicDescription>.size)
        CheckError(AudioUnitGetProperty(player.pointee.inputUnit,
                                        kAudioUnitProperty_StreamFormat,
                                        kAudioUnitScope_Output,
                                        inputBus,
                                        &player.pointee.inputStreamFormat,
                                        &propertySize),
                   "Couldn't get ASBD from input unit")
        
        if debug {
            DebugStreamFormat("Default Input Stream Format", player.pointee.inputStreamFormat)
        }
        
        //Listing 8.9 Adopting Hardware Input Sample Rate
        var deviceFormat = AudioStreamBasicDescription()
        propertySize = (UInt32)(MemoryLayout<AudioStreamBasicDescription>.size)
        CheckError(AudioUnitGetProperty(player.pointee.inputUnit,
                                        kAudioUnitProperty_StreamFormat,
                                        kAudioUnitScope_Input,
                                        inputBus,
                                        &deviceFormat,
                                        &propertySize),
                   "Couldn't get ASBD from input unit")
        if debug {
            DebugStreamFormat("Device Format", deviceFormat)
        }

        player.pointee.inputStreamFormat = deviceFormat
        propertySize = (UInt32)(MemoryLayout<AudioStreamBasicDescription>.size)
        CheckError(AudioUnitSetProperty(player.pointee.inputUnit,
                                        kAudioUnitProperty_StreamFormat,
                                        kAudioUnitScope_Output,
                                        inputBus,
                                        &player.pointee.inputStreamFormat,
                                        propertySize),
                   "Couldn't set ASBD on input unit")

        if debug {
            DebugStreamFormat("Changed Input Stream Format", player.pointee.inputStreamFormat)
        }

        player.pointee.outputStreamFormat = deviceFormat
        player.pointee.outputStreamFormat.mChannelsPerFrame = 2
        player.pointee.outputStreamFormat.mSampleRate = deviceFormat.mSampleRate / 2
        player.pointee.outputStreamFormat.mFormatID = kAudioFormatLinearPCM
        player.pointee.outputStreamFormat.mFormatFlags = kAudioFormatFlagIsNonInterleaved | kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked
        player.pointee.outputStreamFormat.mBytesPerFrame = 4
        player.pointee.outputStreamFormat.mBytesPerPacket = 4

        if debug {
            DebugStreamFormat("Output Stream Format", player.pointee.outputStreamFormat)
        }

        //Listing 8.10 Calculating Capture Buffer Size for an I/O Unit
        var bufferSizeFrames: UInt32 = 0
        propertySize = (UInt32)(MemoryLayout<UInt32>.size)
        CheckError (AudioUnitGetProperty(player.pointee.inputUnit,
                                         kAudioDevicePropertyBufferFrameSize,
                                         kAudioUnitScope_Global,
                                         0,
                                         &bufferSizeFrames,
                                         &propertySize),
                    "Couldn't get buffer frame size from input unit")
        let bufferSizeBytes: UInt32 = bufferSizeFrames * (UInt32)(MemoryLayout<Float32>.size)
        if debug {
            print("● Buffer Size")
            print("Buffer Size Frames : \(bufferSizeFrames)")
            print("Buffer Size Bytes  : \(bufferSizeBytes)")
        }

        //Listing 8.11 Creating an AudioBufferList to Receive Capture Data
        // Allocate an AudioBufferList plus enough space for
        // array of AudioBuffers
        let propsize: UInt32 = UInt32(MemoryLayout.offset(of: \AudioBufferList.mBuffers)!) + (UInt32(MemoryLayout<AudioBuffer>.size) * player.pointee.inputStreamFormat.mChannelsPerFrame)
        // malloc buffer lists
        assert(player.pointee.inputStreamFormat.mChannelsPerFrame == 1)
        player.pointee.inputBuffer = AudioBufferList( mNumberBuffers: player.pointee.inputStreamFormat.mChannelsPerFrame,
                                              mBuffers:
                                                AudioBuffer( mNumberChannels: UInt32(player.pointee.inputStreamFormat.mChannelsPerFrame),
                                                             mDataByteSize: bufferSizeBytes,
                                                             mData: malloc(Int(bufferSizeBytes))))
        player.pointee.converterBuffer = AudioBufferList( mNumberBuffers: player.pointee.inputStreamFormat.mChannelsPerFrame,
                                              mBuffers:
                                                AudioBuffer( mNumberChannels: UInt32(player.pointee.inputStreamFormat.mChannelsPerFrame),
                                                             mDataByteSize: bufferSizeBytes,
                                                             mData: malloc(Int(bufferSizeBytes))))

        // Listing 8.12 Creating a CARingBuffer
        // Alloc ring buffer that will hold data between the
        // two audio devices
//        player.pointee.ringBuffer = CARingBufferWrapper()
        player.pointee.ringBuffer = RingBuffer()
        player.pointee.ringBuffer.allocate(withChannelsPerFrame: player.pointee.inputStreamFormat.mChannelsPerFrame,
                                           bytesPerFrame: player.pointee.inputStreamFormat.mBytesPerFrame,
                                           bufferSize: bufferSizeFrames * 4096)
        
        // Listing 8.13 Setting up an Input Callback on an AUHAL
        // Set render proc to supply samples from input unit
        var callbackStruct =  AURenderCallbackStruct()
        callbackStruct.inputProc = InputRenderProc
        callbackStruct.inputProcRefCon = UnsafeMutableRawPointer(self.player)
        CheckError(AudioUnitSetProperty(player.pointee.inputUnit,
                                        kAudioOutputUnitProperty_SetInputCallback,
                                        kAudioUnitScope_Global,
                                        0,
                                        &callbackStruct,
                                        (UInt32)(MemoryLayout<AURenderCallbackStruct>.size)),
                   "Couldn't set input callback")

        //Listing 8.14 Initializing Input AUHAL and Offset Time Counters
        CheckError(AudioUnitInitialize(player.pointee.inputUnit),
                   "Couldn't initialize input unit")

        player.pointee.firstInputSampleTime = -1
        player.pointee.inToOutSampleTimeOffset = -1
    }

    func createAndConnectOutputUnit(audioDeviceId: AudioDeviceID?) {
        // Generate a description that matches default output
        var outputcd = AudioComponentDescription()
        outputcd.componentType = kAudioUnitType_Output
        outputcd.componentSubType = kAudioUnitSubType_DefaultOutput
        outputcd.componentManufacturer = kAudioUnitManufacturer_Apple
        guard let comp = AudioComponentFindNext(nil, &outputcd) else {
            print("Can't get output unit")
            exit(-1)
        }
        
        CheckError(AudioComponentInstanceNew(comp, &player.pointee.outputUnit),
                   "Couldn't open component for outputUnit")

        let outputBus: AudioUnitScope = 0
        if var _audioDeviceId = audioDeviceId {
            CheckError(AudioUnitSetProperty(player.pointee.outputUnit,
                                            kAudioOutputUnitProperty_CurrentDevice,
                                            kAudioUnitScope_Global,
                                            outputBus,
                                            &_audioDeviceId,
                                            (UInt32)(MemoryLayout<AudioDeviceID>.size)),
                       "Couldn't set output device on I/O unit")
        }

        // Set the stream format on the output unit's input scope
        var propertySize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        CheckError(AudioUnitSetProperty(player.pointee.outputUnit,
                                        kAudioUnitProperty_StreamFormat,
                                        kAudioUnitScope_Input,
                                        0,
                                        &player.pointee.outputStreamFormat,
                                        propertySize),
                   "Couldn't set stream format on output unit")

        var callbackStruct = AURenderCallbackStruct()
        callbackStruct.inputProc = OutputRenderProc
        callbackStruct.inputProcRefCon = UnsafeMutableRawPointer(self.player)
        propertySize = UInt32(MemoryLayout<AURenderCallbackStruct>.size)
        CheckError(AudioUnitSetProperty(player.pointee.outputUnit,
                                        kAudioUnitProperty_SetRenderCallback,
                                        kAudioUnitScope_Global,
                                        0,
                                        &callbackStruct,
                                        propertySize),
                   "Couldn't set render callback on output unit")
        

        // Initialize the unit
        CheckError(AudioUnitInitialize(player.pointee.outputUnit),
                       "Couldn't initialize output unit")

        player.pointee.firstOutputSampleTime = -1
    }

    func start(delayTime: useconds_t) {
        // Start playing
        CheckError(AudioOutputUnitStart(player.pointee.inputUnit),
                   "AudioOutputUnitStart failed")
        usleep(delayTime)
        CheckError(AudioOutputUnitStart(player.pointee.outputUnit),
                    "Couldn't start output unit")
    }
}

func InputRenderProc(_ inRefCon: UnsafeMutableRawPointer,
                     ioActionFlags:UnsafeMutablePointer<AudioUnitRenderActionFlags>,
                     inTimeStamp: UnsafePointer<AudioTimeStamp>,
                     inBusNumber: UInt32,
                     inNumberFrames: UInt32,
                     ioData: UnsafeMutablePointer<AudioBufferList>?) -> OSStatus {
    let player = inRefCon.bindMemory(to: Mono2StereoPlayer.self, capacity: 1)

    //Listing 8.16 Logging Time Stamps from Input AUHAL and Calculating Time Stamp Offset
    // Have we ever logged input timing? (for offset calculation)
    if (player.pointee.firstInputSampleTime < 0.0) {
        DispatchQueue.main.async {
            player.pointee.inputStartTime = Date()
        }
        player.pointee.firstInputSampleTime = inTimeStamp.pointee.mSampleTime
        if ((player.pointee.firstOutputSampleTime >= 0.0) && (player.pointee.inToOutSampleTimeOffset < 0.0)) {
            player.pointee.inToOutSampleTimeOffset = player.pointee.firstInputSampleTime - player.pointee.firstOutputSampleTime
        }
     }

    // サンプルはパラメーターAudioBufferList * ioDataとして提供されると思われるかもしれませんが、
    // そうではありません。入力サンプルの場合、このパラメーターは常にNULLです。
    // 代わりに、コールバックは、キャプチャされたサンプルの準備ができたことを示す単なる
    // シグナルです。リスト8.17に示すように、AudioUnitRender（）を使用してサンプルを自分で取得する必要があります。

    //Listing 8.17 Retrieving Captured Samples from Input AUHAL
    var inputProcErr = noErr
    inputProcErr = AudioUnitRender(player.pointee.inputUnit,
                                   ioActionFlags,
                                   inTimeStamp,
                                   inBusNumber,
                                   inNumberFrames,
                                   &player.pointee.inputBuffer)

    player.pointee.inputDebugCount += 1
    if player.pointee.inputDebugCount % 64 == 0 {
        let buffers = UnsafeMutableAudioBufferListPointer(&player.pointee.inputBuffer)
        var maxValue: Float32 = 0.0
        for buffer in buffers {
            for frame in 0..<Int(inNumberFrames) {
                let p = buffer.mData!.bindMemory(to: Float32.self, capacity: Int(buffer.mDataByteSize)/4)
                maxValue = fmax(maxValue, p[frame])
            }
        }
        DispatchQueue.main.async {
            player.pointee.inputSampleTime = inTimeStamp.pointee.mSampleTime
            player.pointee.inputMaxValue = maxValue
            player.pointee.bufferDiff += Int(inNumberFrames*64)
            player.pointee.inputSamplingRate = Double(player.pointee.inputTotalFrames) / Date().timeIntervalSince(player.pointee.inputStartTime)
        }
    }
    DispatchQueue.main.async {
        player.pointee.inputTotalFrames += Int(inNumberFrames)
    }

    // これが成功した場合は、サンプルをリングバッファにコピーできます。CARingBufferのStore（）メソッドは、
    // この目的のためだけに設計されています。
    // 実際、そのパラメーターリスト（AudioBufferList、framesToWriteカウント、および開始時間）は、
    // 現在スコープ内にある変数とうまく一致しています。この目的のために、前のセクションでAudioBufferListの
    // サイズと割り当てを行い、フレームカウントと リスト8.18に示すように、開始時刻はコールバックのパラメーターとして提供されます。
    
    // Listing 8.18 Storing Captured Samples to a CARingBuffer
    if (inputProcErr == noErr) {
        inputProcErr = player.pointee.ringBuffer.store(withBuffer: &player.pointee.inputBuffer,
                                                       frames: inNumberFrames,
                                                       frameNumber: Int64(inTimeStamp.pointee.mSampleTime))
    }
    if inputProcErr != noErr {
        DispatchQueue.main.async {
            player.pointee.inputErrorCount += 1
        }

    }
    return inputProcErr
}

func OutputRenderProc(_ inRefCon: UnsafeMutableRawPointer,
                      ioActionFlags:UnsafeMutablePointer<AudioUnitRenderActionFlags>,
                      inTimeStamp: UnsafePointer<AudioTimeStamp>,
                      inBusNumber: UInt32,
                      inNumberFrames: UInt32,
                      ioData: UnsafeMutablePointer<AudioBufferList>?) -> OSStatus {
    let player = inRefCon.bindMemory(to: Mono2StereoPlayer.self, capacity: 1)

    //これで作業が始まります。構造体を作成したら、いくつかの「オフセット」時間フィールドを設定します。
    // ここで、リスト8.16でそれらの使用を開始します。入力ユニットと出力ユニットがタイムスタンプに
    // まったく異なるスキームを使用している可能性があるため、これらがあります。
    // 1つは実際の「実時間」時間を使用している可能性があり、もう1つはアプリケーションの起動からの
    // 秒数をカウントしている可能性があります。これは、CARingBufferが追加されたサンプルの
    // タイムスタンプを追跡するため重要です。
    // それらが大きく異なる場合、音は出ません。各ユニットが提供する最初のタイムスタンプに気づき、
    // 両方がある場合は、それらの間の差（またはオフセット）を計算することで、これに対処できます。

    // Have we ever logged output timing? (for offset calculation)
    if (player.pointee.firstOutputSampleTime < 0.0) {
        DispatchQueue.main.async {
            player.pointee.outputStartTime = Date()
        }
        // ある程度バッファが貯まるまでは出力を始めないようにする
//        guard (player.pointee.bufferDiff >= 2048) else {
//            return noErr
//        }
        player.pointee.firstOutputSampleTime = inTimeStamp.pointee.mSampleTime
        if ((player.pointee.firstOutputSampleTime >= 0.0) && (player.pointee.inToOutSampleTimeOffset < 0.0)) {
            player.pointee.inToOutSampleTimeOffset = player.pointee.firstInputSampleTime - player.pointee.firstOutputSampleTime
        }
    }
    
    // 以前と同様に、このオフセット計算は1回だけ実行する必要があります。どちらのコールバックでも、
    // firstInputSampleTimeとfirstOutputSampleTimeの両方に初期化した-1フラグ値以外の値が
    // 最初にあります。
    // 可能なオフセット計算とは別に、このコールバックの実際の作業は、リングバッファーからサンプルを
    // フェッチすることです。これは、リスト8.22に示すように、CARingBufferのFetch（）メソッドへの
    // 1行の呼び出しです。
    
    
    // Copy samples out of ring buffer
    var outputProcErr = noErr
    outputProcErr = player.pointee.ringBuffer.fetch(withBuffer: &player.pointee.converterBuffer,
                                                    frames: inNumberFrames * 2,
                                                    frameNumber: Int64(inTimeStamp.pointee.mSampleTime*2 + player.pointee.inToOutSampleTimeOffset))

    if outputProcErr != noErr {
        DispatchQueue.main.async {
            player.pointee.outputErrorCount += 1
        }
    }

    // ここで、計算されたinToOutSampleTimeOffsetを使用して、バッファーに要求するタイムスタンプを
    // 調整することに注意してください。
    // 最初の出力コールバックが最初の入力コールバックの前に発生した場合、何が起こるのか疑問に思われる
    // かもしれません。その場合、フェッチするリングバッファには何もありません。CARingBufferクラスは、
    // 十分なデータがない場合はいつでも ioDataバッファをゼロ（PCMでは無音）で埋めることにフォールバックします。

    let obuffers = UnsafeMutableAudioBufferListPointer(ioData)!
    let cbuffers = UnsafeMutableAudioBufferListPointer(&player.pointee.converterBuffer)
    let cbuffer = cbuffers.first!

    let cp = cbuffer.mData!.bindMemory(to: Float32.self, capacity: Int(cbuffer.mDataByteSize)/4)
    var ch = 0
    for obuffer in obuffers {
        let op = obuffer.mData!.bindMemory(to: Float32.self, capacity: Int(obuffer.mDataByteSize)/4)
        for frame in 0..<Int(inNumberFrames) {
            op[frame] = cp[frame*2+ch]
        }
        ch += 1
    }

    player.pointee.outputDebugCount += 1
    if player.pointee.outputDebugCount % 64 == 0 {
        var maxValue: Float32 = 0.0
        for buffer in cbuffers {
            let p = buffer.mData!.bindMemory(to: Float32.self, capacity: Int(buffer.mDataByteSize)/4)
            for frame in 0..<Int(inNumberFrames) {
                maxValue = fmax(maxValue, p[frame])
            }
        }
        DispatchQueue.main.async {
            player.pointee.outputSampleTime = inTimeStamp.pointee.mSampleTime
            player.pointee.outputMaxValue = maxValue
            player.pointee.bufferDiff -= Int(inNumberFrames*2*64)
            player.pointee.outputSamplingRate = Double(player.pointee.outputTotalFrames) / Date().timeIntervalSince(player.pointee.outputStartTime)
        }
    }
    DispatchQueue.main.async {
        player.pointee.outputTotalFrames += Int(inNumberFrames)
        let diff = player.pointee.inputTotalFrames - player.pointee.outputTotalFrames*2
        player.pointee.bufferDiffs.append(diff)
        if player.pointee.bufferDiffs.count > 100 {
            player.pointee.bufferDiffs.remove(at: 0)
        }
        player.pointee.bufferDiffAvg = Double(player.pointee.bufferDiffs.reduce(0, +)) / 100.0
    }

    return outputProcErr
}

struct Mono2StereoPlayer {
    var inputStreamFormat :AudioStreamBasicDescription = AudioStreamBasicDescription()
    var outputStreamFormat :AudioStreamBasicDescription = AudioStreamBasicDescription()
    var inputUnit :AudioUnit!
    var outputUnit :AudioUnit!
    var inputBuffer :AudioBufferList!
    var converterBuffer :AudioBufferList!
//    var ringBuffer :CARingBufferWrapper!
    var ringBuffer :RingBuffer!
    var firstInputSampleTime :Float64 = -1
    var firstOutputSampleTime :Float64 = -1
    var inToOutSampleTimeOffset: Float64 = -1

    // for debug
    var inputDebugCount: Int = 0
    var outputDebugCount: Int = 0
    
    var inputErrorCount: Int = 0
    var outputErrorCount: Int = 0
    
    var inputSampleTime: Float64 = 0
    var outputSampleTime: Float64 = 0
    var inputMaxValue :Float32 = -1
    var outputMaxValue :Float32 = -1

    var inputStartTime: Date = Date(timeIntervalSince1970: 0)
    var outputStartTime: Date = Date(timeIntervalSince1970: 0)
    var inputTotalFrames: Int = 0
    var outputTotalFrames: Int = 0
    var inputSamplingRate : Double = 0
    var outputSamplingRate : Double = 0

    var bufferDiff: Int = 0
    var bufferDiffs: [Int] = []
    var bufferDiffAvg: Double = 0
}
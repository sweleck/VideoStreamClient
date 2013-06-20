package {
import flash.events.ActivityEvent;
import flash.events.MouseEvent;
import flash.events.NetStatusEvent;
import flash.events.TimerEvent;
import flash.external.ExternalInterface;
import flash.media.Camera;
import flash.media.H264Level;
import flash.media.H264Profile;
import flash.media.H264VideoStreamSettings;
import flash.media.Microphone;
import flash.media.SoundCodec;
import flash.media.Video;
import flash.net.NetConnection;
import flash.net.NetStream;
import flash.net.Responder;
import flash.net.SharedObject;
import flash.system.Security;
import flash.system.SecurityPanel;

import mx.containers.Canvas;
import mx.containers.Panel;
import mx.controls.Text;
import mx.core.Application;
import mx.core.FlexGlobals;
import mx.core.UIComponent;
import mx.events.FlexEvent;

Security.allowDomain("*");
Security.allowInsecureDomain("*");

public class PublishStreamController extends Application {

	public var videoCamera:Video;
	public var videoCameraContainer:UIComponent;
	public var masterContainer:Canvas;
	public var connectionUrl:String = null;
	public var infoPanel:Panel;
	public var infoText:Text;
	public var debug:Boolean;
	public var autoPublish:Boolean;
	private var nc:NetConnection = null;
	private var camera:Camera;
	private var microphone:Microphone;
	private var nsPublish:NetStream = null;
	private var streamData:String;
	private var dataBW:Object = new Object();
	private var isLoaded:Boolean = false;
	private var startRequest:Boolean = false;
	private var eventCallbackName:String;
	private var sharedObject:SharedObject;

	public function PublishStreamController() {
		addEventListener(FlexEvent.APPLICATION_COMPLETE, mainInit);
	}

	public function startPublish():void {
		startRequest = true;
		if (isLoaded == true && camera.muted == false && nsPublish == null) {
			nsPublish = new NetStream(nc);

			var h264Settings:H264VideoStreamSettings = new H264VideoStreamSettings();
			h264Settings.setProfileLevel(H264Profile.BASELINE, H264Level.LEVEL_3_1);

			nsPublish.videoStreamSettings = h264Settings;
			nsPublish.addEventListener(NetStatusEvent.NET_STATUS, nsPublishOnStatus);
			nsPublish.bufferTime = 0;
			nsPublish.publish("mp4:" + generateRandomPublishName());

			var metaData:Object = new Object();
			metaData.codec = nsPublish.videoStreamSettings.codec;
			metaData.profile = h264Settings.profile;
			metaData.level = h264Settings.level;
			nsPublish.send("@setDataFrame", "onMetaData", metaData);

			nsPublish.attachCamera(camera);
			nsPublish.attachAudio(microphone);
			infoPanel.visible = false;
		}
	}

	public function stopPublish():void {
		nsPublish.attachCamera(null);
		nsPublish.attachAudio(null);
		nsPublish.publish("null");
		nsPublish.close();

		nc.close();
		nc = null;
	}

	public function setMicrophoneLevel(level:String):void {
		var microphoneLevel:Number = 0;
		if (Number(level)) {
			microphoneLevel = Number(level);
		}
		if (microphoneLevel > 1) {
			microphoneLevel = 1;
		} else if (microphoneLevel < 0) {
			microphoneLevel = 0;
		}

		microphone.gain = (microphoneLevel * 100);
		sharedObject.data.microphoneLevel = microphoneLevel;
		sharedObject.flush();

		printMicrophoneLevel();
	}

	protected function scaleVideoToDisplay():void {
		videoCamera.height = masterContainer.height;
		videoCamera.width = masterContainer.height * 1.33;
	}

	private function mainInit(event:FlexEvent):void {
		videoCamera = new Video(videoCameraContainer.width, videoCameraContainer.height);
		videoCameraContainer.addChild(videoCamera);
		connectionUrl = FlexGlobals.topLevelApplication.parameters.connectionUrl;
		streamData = FlexGlobals.topLevelApplication.parameters.streamData;
		eventCallbackName = FlexGlobals.topLevelApplication.parameters.eventCallback;
		autoPublish = ((FlexGlobals.topLevelApplication.parameters.autoPublish == "true"));
		debug = ((FlexGlobals.topLevelApplication.parameters.debug == "true"));

		sharedObject = SharedObject.getLocal('settings');
		if (!sharedObject.data.hasOwnProperty('microphoneLevel')) {
			sharedObject.data.microphoneLevel = 1;
			sharedObject.flush();
		}

		ExternalInterface.addCallback("startPublish", startPublish);
		ExternalInterface.addCallback("stopPublish", stopPublish);
		ExternalInterface.addCallback("setMicrophoneLevel", setMicrophoneLevel);
		initCamera();
		if (camera.muted) {
			Security.showSettings(SecurityPanel.PRIVACY);
		}
		scaleVideoToDisplay();
	}

	private function initCamera():void {
		setCamera();

		microphone = Microphone.getMicrophone();
		microphone.rate = 11;
		microphone.setSilenceLevel(0);
		microphone.codec = SoundCodec.SPEEX;
		microphone.encodeQuality = 5;
		microphone.framesPerPacket = 2;
		microphone.gain = (sharedObject.data.microphoneLevel * 100);
		printMicrophoneLevel();
	}

	private function cameraActivityHandler(event:ActivityEvent):void {
		doConnect();
	}

	private function ncOnStatus(infoObject:NetStatusEvent):void {
		if (debug) {
			ExternalInterface.call('console.log', "ncOnStatus: " + infoObject.info.code + " (" + infoObject.info.description + ")");
		}
		switch (infoObject.info.code) {
			case "NetConnection.Connect.Closed":
				connectionLostNotification();
				break;
			case "NetStream.Play.Failed":
				connectionLostNotification();
				break;
			case "NetConnection.Connect.Failed":
				connectionLostNotification();
				break;
		}

		nc.call("onClientBWCheck", new Responder(bandwidthCheckHandler));
	}

	private function nsPublishOnStatus(infoObject:NetStatusEvent):void {
		if (debug) {
			ExternalInterface.call('console.log', "nsPublishHere: " + infoObject.info.code + " (" + infoObject.info.description + ")");
		}
		switch (infoObject.info.code) {
			case "NetStream.Play.StreamNotFound":
				connectionLostNotification();
				break;
			case "NetStream.Play.Failed":
				connectionLostNotification();
				break;
			case "NetConnection.Connect.Failed":
				connectionLostNotification();
				break;
		}
	}

	private function doConnect():void {
		if (nc == null) {
			nc = new NetConnection();
			nc.connect(connectionUrl, streamData);
			nc.addEventListener(NetStatusEvent.NET_STATUS, ncOnStatus);
			checkBandwidth();
		}
	}

	private static function generateRandomPublishName():String {
		var a:String = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
		var alphabet:Array = a.split("");
		var publishName:String = "";
		for (var i:Number = 0; i < 32; i++) {
			publishName += alphabet[Math.floor(Math.random() * alphabet.length)];
		}
		return publishName;
	}

	private function connectionLostNotification():void {
		videoCamera.clear();
		videoCamera.attachCamera(null);
		microphone.setLoopBack(false);
		printError("Connection Lost", "connectionlost");
	}

	private function checkBandwidth():void {
		dataBW.latency = 0;
		dataBW.cumLatency = 1;
		dataBW.bwTime = 0;
		dataBW.count = 0;
		dataBW.sent = 0;
		dataBW.kbitUp = 0;
		dataBW.deltaUp = 0;
		dataBW.deltaTime = 0;
		dataBW.pakSent = new Array();
		dataBW.pakRecv = new Array();
		dataBW.beginningValues = {};

		nc.call("onClientBWCheck", new Responder(bandwidthCheckHandler));
	}


	private function bandwidthCheckHandler(bwResponse:Object):void {
		var deltaTime:Number;
		var deltaUp:Number;
		var kbitUp:Number;
		var payload:Array = new Array();
		for (var i:int = 0; i < 1200; i++) {
			payload[i] = Math.random();
		}

		var now:Number = (new Date()).getTime();

		if (dataBW.sent == 0) {
			dataBW.beginningValues = bwResponse;
			dataBW.beginningValues.time = now;
			dataBW.pakSent[dataBW.sent++] = now;
			nc.call("onClientBWCheck", new Responder(bandwidthCheckHandler), now);
		} else {
			dataBW.pakRecv[dataBW.count] = now;
			dataBW.count++;

			var timePassed:Number = (now - dataBW.beginningValues.time);

			if (dataBW.count == 1) {
				dataBW.latency = Math.min(timePassed, 800);
				dataBW.latency = Math.max(dataBW.latency, 10);
				dataBW.overhead = bwResponse.cOutBytes - dataBW.beginningValues.cOutBytes;
				dataBW.pakSent[dataBW.sent++] = now;

				nc.call("onClientBWCheck", new Responder(bandwidthCheckHandler), now, payload);
			}

			if ((dataBW.count > 1) && (timePassed < 1000)) {
				dataBW.pakSent[dataBW.sent++] = now;
				dataBW.cumLatency++;
				nc.call("onClientBWCheck", new Responder(bandwidthCheckHandler), now, payload);
			} else if (dataBW.sent != dataBW.count) {
			} else {
				if (dataBW.latency >= 100) {
					if (dataBW.pakRecv[1] - dataBW.pakRecv[0] > 1000) {
						dataBW.latency = 100;
					}
				}

				deltaUp = (bwResponse.cOutBytes - dataBW.beginningValues.cOutBytes) * 8 / 1000;
				deltaTime = ((now - dataBW.beginningValues.time) - (dataBW.latency * dataBW.cumLatency) ) / 1000;
				if (deltaTime <= 0) {
					deltaTime = (now - dataBW.beginningValues.time) / 1000;
				}

				kbitUp = Math.round(deltaUp / deltaTime);
				if (debug) {
					ExternalInterface.call('console.log', "KbitTest: " + kbitUp + " current FPS: " + camera.currentFPS);
				}
				var cameraWidthMax:Number = 1280;
				var width:Number = Math.min(cameraWidthMax, kbitUp * 1.2);
				var minFPS:Number = 20;
				if (camera.currentFPS < minFPS) {
					width *= camera.currentFPS / minFPS;
				}
				var cameraWidthMin:Number = 320;
				width = Math.max(cameraWidthMin, width);
				var ratio:Number = 4 / 3;
				var height:Number = width / ratio;

				setCamera(width, height);

				if (height != camera.height || width != camera.width) {
					if (camera.height * ratio > camera.width) {
						height = camera.width / ratio;
					} else {
						width = camera.height * ratio;
					}
					setCamera(width, height);
				}
				if (debug) {
					ExternalInterface.call('console.log', "camera set to: " + camera.width + " x " + camera.height);
				}

				isLoaded = true;
				if (startRequest == true || autoPublish == true) {
					startPublish();
				}

				infoPanel.visible = false;
			}
		}
	}

	private function setCamera(width:Number = 0, height:Number = 0):void {
		try {
			camera = null;
			videoCamera.clear();
			videoCamera.attachCamera(null);
			camera = Camera.getCamera();

			if (camera == null) {
				throw new ErrorNoCam();
			}

			camera.setQuality(0, 80);
			if (width != 0) {
				camera.setMode(width, height, 24);
			}
			camera.addEventListener(ActivityEvent.ACTIVITY, cameraActivityHandler);

			videoCamera.clear();
			videoCamera.attachCamera(camera);
		} catch (errorNoCam:ErrorNoCam) {
			printError(errorNoCam.message, "nocam");
		} catch (error:Error) {
			printError(error.message, "unknown");
		}
	}

	private function printError(message:String, type:String):void {
		infoPanel.title = "Error: ";
		infoText.text = message;
		infoPanel.visible = true;
		var data:Object = new Object();
		data["type"] = type;
		data["message"] = message;
		eventCallback("error", data);
	}

	private function printMicrophoneLevel():void {
		var data:Object = new Object();
		data["level"] = (microphone.gain / 100);
		eventCallback("microphoneLevel", data);
	}

	private function eventCallback(type:String, data:Object):void {
		var callbackObject:Object = new Object();
		callbackObject["type"] = type;
		callbackObject["data"] = data;
		ExternalInterface.call(eventCallbackName, JSON.stringify(callbackObject));
	}

}
}

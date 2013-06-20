package {
import flash.display.StageDisplayState;
import flash.events.NetStatusEvent;
import flash.external.*;
import flash.media.SoundTransform;
import flash.media.Video;
import flash.net.NetConnection;
import flash.net.NetStream;
import flash.net.SharedObject;
import flash.system.Security;

import mx.containers.Canvas;
import mx.containers.Panel;
import mx.controls.Text;
import mx.core.Application;
import mx.core.FlexGlobals;
import mx.core.UIComponent;
import mx.events.FlexEvent;

Security.allowDomain("*");
Security.allowInsecureDomain("*");

public class SubscribeStreamController extends Application {

	public var videoRemoteContainer:UIComponent;
	public var connectionUrl:String = null;
	public var streamName:String = null;
	public var masterContainer:Canvas;
	public var infoPanel:Panel;
	public var infoText:Text;
	public var debug:Boolean;
	private var nc:NetConnection = null;
	private var nsPlay:NetStream = null;
	private var videoRemote:Video;
	private var streamData:Object;
	private var sharedObject:SharedObject;
	private var t:SoundTransform = new SoundTransform();
	private var eventCallbackName:String;

	public function SubscribeStreamController() {
		addEventListener(FlexEvent.APPLICATION_COMPLETE, mainInit);
	}

	public function setVolume(volumeLevel:String):void {
		var volume:Number = 0;
		if (Number(volumeLevel)) {
			volume = Number(volumeLevel);
		}
		if (volume > 1) {
			volume = 1;
		} else if (volume < 0) {
			volume = 0;
		}

		sharedObject.data.volume = volume;
		sharedObject.flush();
		sharedObject.close();
		printVolume();
		if (null === nsPlay) return;

		t.volume = sharedObject.data.volume;
		nsPlay.soundTransform = t;
	}

	private function mainInit(event:FlexEvent):void {
		videoRemote = new Video();
		videoRemoteContainer.addChild(videoRemote);

		connectionUrl = FlexGlobals.topLevelApplication.parameters.connectionUrl;
		eventCallbackName = FlexGlobals.topLevelApplication.parameters.eventCallback;
		streamName = FlexGlobals.topLevelApplication.parameters.streamName;
		streamData = FlexGlobals.topLevelApplication.parameters.streamData;
		debug = ((FlexGlobals.topLevelApplication.parameters.debug == "true"));

		ExternalInterface.addCallback('setVolume', setVolume);

		sharedObject = SharedObject.getLocal("settings");
		if (!sharedObject.data.hasOwnProperty('volume')) {
			sharedObject.data.volume = 1;
		}

		scaleVideoToDisplay();
		doConnect();
	}

	private function ncOnStatus(infoObject:NetStatusEvent):void {
		if (debug) {
			ExternalInterface.call('console.log', "nc: " + infoObject.info.code + " (" + infoObject.info.description + ")");
		}

		switch (infoObject.info.code) {
			case "NetConnection.Connect.Failed":
				printError("Connection Failed", "connectionlost");
				break;
			case "NetConnection.Connect.Rejected":
				printError("Connection Rejected", "connectionlost");
				break;
			case "NetConnection.Connect.Closed":
				printError("Connection Closed", "connectionlost");
				break;
			default:
				subscribe();
				break;
		}
	}

	private function doConnect():void {
		if (nc == null) {
			nc = new NetConnection();
			nc.connect(connectionUrl, streamData);
			nc.addEventListener(NetStatusEvent.NET_STATUS, ncOnStatus);
		}
	}

	private function nsPlayOnStatus(infoObject:NetStatusEvent):void {
		switch (infoObject.info.code) {
			case "NetStream.Play.Failed":
				printError("Could not Play", "connectionlost");
				break;
			case "NetStream.Play.StreamNotFound":
				printError("Stream Not Found", "connectionlost");
				break;
		}
	}

	private function subscribe(quality:String = ''):void {
		if (quality == null) {
			quality = '';
		}

		if (nsPlay != null) {
			nsPlay.close();
			videoRemote.attachNetStream(null);
		}

		nsPlay = new NetStream(nc);
		nsPlay.addEventListener(NetStatusEvent.NET_STATUS, nsPlayOnStatus);
		nsPlay.client = new Object();
		nsPlay.bufferTime = 0;

		nsPlay.play(streamName + quality);
		t.volume = sharedObject.data.volume;
		nsPlay.soundTransform = t;
		printVolume();

		videoRemote.attachNetStream(nsPlay);
		infoPanel.visible = false;
	}

	protected function scaleVideoToDisplay():void {
		videoRemote.height = masterContainer.height;
		if (stage.displayState == StageDisplayState.NORMAL) {
			videoRemote.width = masterContainer.height * 1.33;
		} else {
			videoRemote.width = masterContainer.width;
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

	private function printVolume():void {
		var data:Object = new Object();
		data["level"] = (sharedObject.data.volume);
		eventCallback("volume", data);
	}

	private function eventCallback(type:String, data:Object):void {
		var callbackObject:Object = new Object();
		callbackObject["type"] = type;
		callbackObject["data"] = data;
		ExternalInterface.call(eventCallbackName, JSON.stringify(callbackObject));
	}

}
}
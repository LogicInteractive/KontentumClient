package client;

import com.akifox.asynchttp.HttpRequest;
import com.akifox.asynchttp.HttpResponse;
import fox.files.File;
import fox.files.Files;
import fox.loader.Loader;
import fox.utils.DateUtils;
import haxe.Exception;
import haxe.Json;
import haxe.Timer;
import sys.FileStat;
import sys.FileSystem;

class HostedFileSync
{
	/////////////////////////////////////////////////////////////////////////////////////

	static public var i				: HostedFileSync;
	static public var isEnabled		: Bool				= false;

	var MAX_SIZE					: Int				= 2000000000;
	var syncURL						: String;
	var hostedBaseURL				: String;
	var fileListRequest				: HttpRequest;

	var localPath					: String;
	var fileList					: Array<HostedFile>;
	var filesInDir					: Files;

	/////////////////////////////////////////////////////////////////////////////////////

    static public function init():Bool
	{
		isEnabled = Settings.config.kontentum!=null && Settings.config.kontentum.hosted!=null;
		if (isEnabled)
			i = new HostedFileSync();

		return isEnabled;
	}

	/////////////////////////////////////////////////////////////////////////////////////

    public function new()
	{
		localPath = Settings.config.kontentum.hosted.localpath!=null ? Settings.config.kontentum.hosted.localpath : "";

        hostedBaseURL = Settings.config.kontentum.ip+'/hosted/'+Settings.config.kontentum.hosted.folder;
        syncURL = Settings.config.kontentum.ip+'/'+Settings.config.kontentum.hosted.api+'/'+Settings.config.kontentum.hosted.folder;

		fileListRequest = new HttpRequest( { url:syncURL, callback:onHttpResponse, callbackError:onHttpError });
		fileListRequest.timeout = 60*3;		
		fileListRequest.send();
    }

	/////////////////////////////////////////////////////////////////////////////////////

	function onHttpError(response:HttpResponse) 
	{
		if (Settings.debug)
		{
			Sys.println("HTTP error : filesync rest problem: "+response.toString());
			Sys.println("Will retry...");
		}

		Timer.delay(()->
		{
			fileListRequest = fileListRequest.clone();
			fileListRequest.send();
			
		},3000);
	}
	
	function onHttpResponse(response:HttpResponse)
	{
		if (response.isOK)
		{
			if (response.content != null)
			{
				try 
				{
					var jsn:Dynamic = Json.parse(response.content);
					if (jsn==null)
					{
						if (Settings.debug)
							Sys.println("Error: HTTP filesync JSON data corrupt");
					}
					else 
					{
						fileList = jsn.files;
						if (fileList==null)
						{
							if (Settings.debug)
								Sys.println("Error: HTTP filesync JSON data corrupt");
						}
						else
						{
							for (i in 0...fileList.length)
							{
								fileList[i].date = Date.fromString(fileList[i].timestamp);
								fileList[i].remotePath = hostedBaseURL+'/'+fileList[i].path;
							}

							syncFiles();
						}
					}
							
				}
				catch(e:Exception)
				{
					if (Settings.debug)
						Sys.println("Error: HTTP filesync JSON error: "+e.message);
				}
			}
		}
		else
			onHttpError(response);
	}

	/////////////////////////////////////////////////////////////////////////////////////

	function syncFiles()
	{
		var fl:Array<String> = [];
		for (f in fileList)
			fl.push(f.path);

		filesInDir = new Files(localPath, true, true, false);
		deleteNonExistingFiles(filesInDir,fl);
		
		var numFilesToDownload:Int = 0;
		for (hf in fileList) 
		{
			var shouldAdd:Bool = true;
			if (FileSystem.exists(localPath+'/'+hf.path))
			{
				var fi:FileStat = FileSystem.stat(localPath+'/'+hf.path);
				if (DateUtils.isOlderThan(hf.date,fi.mtime))
					shouldAdd = false;
			}

			if (hf.size>MAX_SIZE)
				shouldAdd = false;

			if (shouldAdd)
			{
				var dlFile:String = hf.remotePath;
				if (dlFile!=null && dlFile!="null")
				{
					Loader.addToQueue(dlFile,{data:hf});
					numFilesToDownload++;
				}
			}	
		}	
		
		if (numFilesToDownload==0)
			return;

		Sys.println('/// KONTENTUM HOSTED SYNC  |  Download : $numFilesToDownload ///');
		Sys.println('');

		Loader.onQueueItemStartedCallback = onQueueItemStarted;
		Loader.onQueueItemProgressCallback = onQueueItemProgress;
		Loader.onQueueItemCompleteCallback = onQueueItemCompleted;
		Loader.onQueueItemLoadErrorCallback = onQueueItemError;
		Loader.onQueueCompleteCallback = onQueueCompleted;
		var fileDownloader = Loader.downloadQueue(localPath,null,null,null,null,null,false);

		// for (f in fileList)
			// Sys.println(f.remotePath);
	}

	function onQueueItemStarted(ld:Loader)
	{
		Sys.println("Downloading "+ld.fileName+" .......");
	}

	function onQueueItemProgress(ld:Loader)
	{
		// var numList:String = "["+(Loader.loaderQueueIndex+1)+"/"+Loader.loaderQueue.length+"] ";
		// downloadFilesProgressString = numList+ld.fileName +" : "+StringUtils.floatToString(ld.bytesLoaded/1024,1)+" kB / "+StringUtils.floatToString(ld.bytesTotal/1024,1)+" kB [ "+StringUtils.floatToString(ld.loadingProgress*100,1)+"% ]";
		// if (onDownloadFilesProgress!=null)
			// onDownloadFilesProgress();
	}

	function onQueueItemCompleted(ld:Loader)
	{
		if (ld.data==null)
			return;
			
		var hf:HostedFile = ld.data;
		if (hf!=null)
		{
			var ret = filesInDir.saveBinaryFile(hf.path,ld.contentRAW,true);
			if (!ret)
				Sys.println("ERROR: Failed to save file: "+filesInDir.currentDir+'/'+hf.path);
		}
		// if (onDownloadFilesItemComplete!=null)
			// onDownloadFilesItemComplete();
	}

	function onQueueItemError(ld:Loader)
	{
		Sys.println("ERROR: Failed to download: "+ld.source);
	}

	function onQueueCompleted()
	{
		// trace("All files downloaded!!");
		Sys.println("HOSTED file sync complete.");
	}
	
	function deleteNonExistingFiles(filesInDir:Files,sourceFiles:Array<String>)
	{
		var newFiles:Array<File> = [];
		var markedForDeletion:Array<File> = [];
		
		if (filesInDir != null)
		{
			for (j in 0...filesInDir.currentDirFiles.length) 
			{
				var df:String = filesInDir.currentDirFiles[j].fileName;
				var found:Bool = false;
				
				for (nfl in sourceFiles) 
				{
					if (nfl==df)
					{
						found = true;
						break;
					}
				}
				if (!found)
					markedForDeletion.push(filesInDir.currentDirFiles[j]);
			}
			
 			for (k in 0...markedForDeletion.length) 
			{
				var fnn:File = markedForDeletion[k];
				if (fnn!=null && fnn.isValid)
				{
					fnn.delete();
				}
			}
			filesInDir.readDir();
		}
	}
	
	/////////////////////////////////////////////////////////////////////////////////////
}

typedef HostedFile =
{
	var path		: String;
	var remotePath	: String;
	var timestamp	: String;
	var size		: Int;
	var date		: Date;
}
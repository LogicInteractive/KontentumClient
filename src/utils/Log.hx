package utils;

import DateTools;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

class Log
{
	static var logDir:String;
	static var logFile:String;
	static var maxBytes:Int = 5 * 1024 * 1024; // 5 MB

	public static function init(?dir:String):Void
	{
		// Put logs directly in exe folder (no subfolder)
		if (dir == null)
		{
			var exePath = Sys.programPath();
			logDir = Path.directory(exePath);
		}
		else
		{
			logDir = dir;
		}

		// Ensure directory exists
		if (!FileSystem.exists(logDir))
		{
			try
			{
				FileSystem.createDirectory(logDir);
			}
			catch (_:Dynamic)
			{
				// Already should exist since it's the exe directory
			}
		}

		logFile = Path.join([logDir, "client.log"]);

		// Funnel haxe trace:
		haxe.Log.trace = function (v:Dynamic, ?infos:haxe.PosInfos):Void
		{
			var where = infos != null ? '${infos.className}.${infos.methodName}:${infos.lineNumber}' : '';
			write('[TRACE] ' + where + '  ' + Std.string(v));
		};
		write("=== KontentumClient start " + Date.now().toString() + " ===");
	}

	public static inline function path():String
	{
		return logFile;
	}

	public static function write(msg:String):Void
	{
		var line = '[' + DateTools.format(Date.now(), "%H:%M:%S") + '] ' + msg + "\r\n";
		try
		{
			// Ensure file can be written
			var output = File.append(logFile, false);
			output.writeString(line);
			output.close();
		}
		catch (e:Dynamic)
		{
			// If file write fails, at least show it on console
			#if sys
			Sys.println('[LOG ERROR] Failed to write to: $logFile - ${Std.string(e)}');
			#end
		}
		#if sys
		Sys.println(StringTools.replace(line, "\r\n", ""));
		#end
		rotateIfNeeded();
	}

	static function rotateIfNeeded():Void
	{
		try
		{
			if (FileSystem.exists(logFile))
			{
				var st = FileSystem.stat(logFile);
				if (st.size > maxBytes)
				{
					var ts = DateTools.format(Date.now(), "%H%M%S");
					var rotated = StringTools.replace(logFile, ".log", "-" + ts + ".log");
					FileSystem.rename(logFile, rotated);
				}
			}
		}
		catch (_:Dynamic) {}
	}

	public static function logException(prefix:String, e:Dynamic):Void
	{
		write(prefix + ": " + Std.string(e));
		// Try to dump Haxe call stacks when available
		try
		{
			var s1 = haxe.CallStack.toString(haxe.CallStack.exceptionStack());
			var s2 = haxe.CallStack.toString(haxe.CallStack.callStack());
			if (s1 != null && s1 != "") write("Exception stack:\n" + s1);
			if (s2 != null && s2 != "") write("Call stack:\n" + s2);
		}
		catch (_:Dynamic) {}
	}
}

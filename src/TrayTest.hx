class TrayTest
{
	static function main()
	{
		Sys.println("Initializing tray test...");

		var success = utils.Tray.init("Test Tray");
		Sys.println("Tray init: " + success);

		utils.Tray.useEmbeddedIcon();
		Sys.println("Icon set");

		// Simple timer to pump and check commands
		var count = 0;
		var timer = new haxe.Timer(150);
		timer.run = function()
		{
			utils.Tray.pump();
			count++;

			// Show pump count every second (every ~7 ticks at 150ms)
			if (count % 7 == 0)
			{
				Sys.println("Pump " + count + " (ticks every 150ms)");
			}

			var cmd = utils.Tray.pollCommand();
			if (cmd != 0)
			{
				Sys.println(">>> Command received: " + cmd + " <<<");

				switch (cmd)
				{
					case utils.Tray.CMD_QUIT:
						Sys.println(">>> Quit requested <<<");
						utils.Tray.destroy();
						Sys.exit(0);
					case utils.Tray.CMD_SHOW_LOGS:
						Sys.println(">>> Show logs requested <<<");
					case utils.Tray.CMD_RESTART:
						Sys.println(">>> Restart requested <<<");
				}
			}
		};

		Sys.println("Timer created and callback set");

		Sys.println("Tray test running. Right-click the tray icon.");
		Sys.println("Press Ctrl+C to exit or choose Quit from tray menu.");

		// Keep program running with proper event loop
		haxe.MainLoop.add(function() {});
	}
}

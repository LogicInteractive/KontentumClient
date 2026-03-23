package;

import fox.native.windows.Chrome;
import haxe.Timer;

/**
 * Standalone test for Chrome crash detection
 * This test launches Chrome and verifies the checkAlive() method works
 */
class TestChromeCrash
{
    static var chrome:Chrome;
    static var checkCount:Int = 0;
    static var testPassed:Bool = false;

    static public function main()
    {
        trace("=================================================");
        trace("Chrome Crash Detection Test");
        trace("=================================================");
        trace("");

        // Set Chrome location
        Chrome.exeLocation = "C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe";

        trace("[1] Launching Chrome with test URL...");
        chrome = Chrome.launch("https://www.google.com");

        trace("[1] Chrome launched. Edge should open in kiosk mode.");
        trace("");

        trace("[2] Setting up monitoring timer (checks every 1 second)...");
        var monitorTimer = new Timer(1000);
        monitorTimer.run = function() {
            checkCount++;
            var isAlive = chrome.checkAlive();

            if (isAlive) {
                trace('[${checkCount}] Chrome is alive ✓');

                // After 3 successful checks, tell user to kill Chrome
                if (checkCount == 3) {
                    trace("");
                    trace("=================================================");
                    trace("TEST INSTRUCTION:");
                    trace("Please KILL the Edge/Chrome process now!");
                    trace("(Open Task Manager and End Task on msedge.exe)");
                    trace("=================================================");
                    trace("");
                }
            } else {
                trace('[${checkCount}] Chrome is DEAD ✗');
                trace("");
                trace("=================================================");
                trace("TEST RESULT: SUCCESS!");
                trace("Crash detection is working correctly!");
                trace("checkAlive() correctly detected the process died.");
                trace("=================================================");

                monitorTimer.stop();
                testPassed = true;

                // Wait a bit then exit
                Timer.delay(function() {
                    trace("");
                    trace("Exiting test...");
                    Sys.exit(0);
                }, 2000);
            }

            // Safety timeout after 30 checks
            if (checkCount >= 30) {
                trace("");
                trace("=================================================");
                trace("TEST RESULT: TIMEOUT");
                trace("User did not kill Chrome within 30 seconds.");
                trace("Test cannot verify crash detection.");
                trace("=================================================");
                monitorTimer.stop();
                Sys.exit(1);
            }
        };

        trace("[2] Monitoring started. Waiting for Chrome to die...");
        trace("");
    }
}
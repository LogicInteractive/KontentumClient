package;

import fox.compile.CompileTime;
import fox.utils.DateUtils;
import utils.WindowsUtils;

var buildDate : Date			= CompileTime.buildDate();

/////////////////////////////////////////////////////////////////////////////////////

function printLogo()
{
	var date = DateUtils.getFormattedDate(buildDate);

	Sys.println('====================================================');
	Sys.println('                                                    ');
	Sys.println('   ##                               ##              ');
	Sys.println('   ##                                               ');
	Sys.println('   ##     ############################  #########   ');
	Sys.println('   ##     ##           ##           ##  ##          ');
	Sys.println('   ##     ##       ##  ##       ##  ##  ##          ');
	Sys.println('   ##              ##  ##       ##  ##  ##          ');
	Sys.println('   ##################  #######  ##  ##  #######     ');
	Sys.println('                                ##                  ');
	Sys.println('                                ##                  ');
	Sys.println('                       ###########                  ');
	Sys.println('                                                    ');
	Sys.println('     I   N   T   E   R   A   C   T   I   V   E      ');
	Sys.println('                                                    ');
	Sys.println('     // Build : $date ');
	Sys.println('                                                    ');
	Sys.println('====================================================');
}


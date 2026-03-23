class TestArgs {
	static function main() {
		var args = Sys.args();
		Sys.println("Argument count: " + args.length);
		for (i in 0...args.length) {
			Sys.println('  arg[${i}] = "${args[i]}"');
		}
	}
}

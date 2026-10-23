using System;
using System.IO;
using System.Collections.Generic;

class InstallerLauncherProbe
{
    static int Main(string[] args)
    {
        string temp = Environment.GetEnvironmentVariable("TEMP");
        string tmp = Environment.GetEnvironmentVariable("TMP");
        string probe = Path.Combine(temp, "child-write-test");
        File.WriteAllText(probe, "ok");
        File.Delete(probe);
        var lines = new List<string> { temp, tmp };
        lines.AddRange(args);
        File.WriteAllLines(Environment.GetEnvironmentVariable("SP_PROBE_OUTPUT"), lines);
        return int.Parse(Environment.GetEnvironmentVariable("SP_PROBE_EXIT"));
    }
}

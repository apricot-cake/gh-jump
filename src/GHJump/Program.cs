using Microsoft.CommandPalette.Extensions;
using Shmuelie.WinRTServer;
using Shmuelie.WinRTServer.CsWinRT;

namespace GHJump;

internal static class Program
{
    [MTAThread]
    private static void Main(string[] args)
    {
        if (args.Length == 0 || args[0] != "-RegisterProcessAsComServer")
        {
            return;
        }

        using var disposed = new ManualResetEvent(false);
        var extension = new JumpExtension(disposed);
        var server = new ComServer();
        try
        {
            server.RegisterClass<JumpExtension, IExtension>(() => extension);
            server.Start();
            disposed.WaitOne();
        }
        finally
        {
            server.Stop();
            server.UnsafeDispose();
        }
    }
}

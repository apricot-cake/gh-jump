using System.Runtime.InteropServices;
using Microsoft.CommandPalette.Extensions;

namespace GHJump;

[Guid("CD969A05-A92B-49AC-90AB-69DA0B998467")]
public sealed partial class JumpExtension : IExtension, IDisposable
{
    private readonly ManualResetEvent _disposed;
    private readonly JumpCommandsProvider _provider = new();

    public JumpExtension(ManualResetEvent disposed) => _disposed = disposed;

    public object? GetProvider(ProviderType providerType) =>
        providerType == ProviderType.Commands ? _provider : null;

    public void Dispose()
    {
        _provider.Dispose();
        _disposed.Set();
    }
}

namespace Grenis.AudioBooks.Core;

public record ChangePasswordRequest(string CurrentPassword, string NewPassword);
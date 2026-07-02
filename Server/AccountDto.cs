namespace Server;

public record AccountDto(int Id, string Email);
public record ChangeEmailRequest(string NewEmail, string CurrentPassword);
public record ChangePasswordRequest(string CurrentPassword, string NewPassword);

public record AuthResponse(string Token);
public record EmailChangeResponse(string Token, string Email);
public record MessageResponse(string Message);
public record FavoriteResponse(bool IsFavorite);
public record RescanResponse(int Count);

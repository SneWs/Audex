namespace Grenis.AudioBooks.Server.Database.Tables;
public class User
{
    public int Id { get; set; }
    public string Email { get; set; } = default!;
    public string PasswordHash { get; set; } = default!;
    public bool PrefersDarkMode { get; set; }
}

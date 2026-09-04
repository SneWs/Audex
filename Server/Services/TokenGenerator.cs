using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using Grenis.AudioBooks.Server.Database.Tables;
using Microsoft.IdentityModel.Tokens;

namespace Grenis.AudioBooks.Server;

public class TokenGenerator
{
    private readonly SigningCredentials _signingCredentials;

    public TokenGenerator(SymmetricSecurityKey key) =>
        _signingCredentials = new SigningCredentials(key, SecurityAlgorithms.HmacSha256);

    public string GenerateToken(User user)
    {
        var claims = new[]
        {
            new Claim(ClaimTypes.NameIdentifier, user.Id.ToString()),
            new Claim(ClaimTypes.Email, user.Email)
        };
        var jwt = new JwtSecurityToken(
            claims: claims,
            expires: DateTime.UtcNow.AddDays(7),
            signingCredentials: _signingCredentials);
        return new JwtSecurityTokenHandler().WriteToken(jwt);
    }
}

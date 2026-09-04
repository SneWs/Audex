using System.Text;
using Grenis.AudioBooks.Server;
using Grenis.AudioBooks.Server.Database;
using Grenis.AudioBooks.Server.Endpoints;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.Tokens;
using Microsoft.OpenApi;

var builder = WebApplication.CreateBuilder(args);

if (string.IsNullOrEmpty(builder.Configuration["Jwt:Secret"])) throw new Exception("JWT secret missing");

builder.Services.AddDbContext<AppDbContext>(opt =>
    opt.UseNpgsql(builder.Configuration.GetConnectionString("DefaultConnection")));

var settings = builder.Configuration.GetSection("AudiobookSettings").Get<AudiobookSettings>()
    ?? throw new Exception("AudiobookSettings missing");
builder.Services.AddSingleton(Options.Create(settings));

builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(options =>
{
    options.SwaggerDoc("v1", new Microsoft.OpenApi.OpenApiInfo
    {
        Title = "Audiobook Library API",
        Version = "v1",
        Description = "REST API for the Audiobook Library: browse books, stream chapters, track progress, manage favorites and account."
    });

    const string schemeId = "Bearer";
    options.AddSecurityDefinition(schemeId, new Microsoft.OpenApi.OpenApiSecurityScheme
    {
        Name = "Authorization",
        Type = Microsoft.OpenApi.SecuritySchemeType.Http,
        Scheme = "bearer",
        BearerFormat = "JWT",
        In = Microsoft.OpenApi.ParameterLocation.Header,
        Description = "Enter the JWT returned by /api/login or /api/register (no 'Bearer' prefix needed)."
    });
    options.AddSecurityRequirement(doc => new Microsoft.OpenApi.OpenApiSecurityRequirement
    {
        { new Microsoft.OpenApi.OpenApiSecuritySchemeReference(schemeId, doc, null), new List<string>() }
    });
});

var key = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(builder.Configuration["Jwt:Secret"]!));
builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        options.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer = false,
            ValidateAudience = false,
            ValidateLifetime = true,
            ValidateIssuerSigningKey = true,
            IssuerSigningKey = key
        };
    });
builder.Services.AddAuthorization();
builder.Services.AddSingleton(new TokenGenerator(key));

builder.Services.AddHttpClient<BookMetadataLookup>(client =>
{
    client.DefaultRequestHeaders.Add("User-Agent", "Audex/1.0");
    client.Timeout = TimeSpan.FromSeconds(15);
});
builder.Services.AddHttpClient<IAudibleBookScraper, AudibleBookScraper>(client =>
{
    client.DefaultRequestHeaders.Add("User-Agent", "Audex/1.0 (+https://audex.local)");
    client.Timeout = TimeSpan.FromSeconds(15);
});
builder.Services.AddSignalR();
builder.Services.AddScoped<IAudioIndexer, AudioIndexer>();
builder.Services.AddHostedService<AudioIndexBackgroundService>();

builder.Services.AddCors(options =>
    options.AddDefaultPolicy(p => p.AllowAnyOrigin().AllowAnyHeader().AllowAnyMethod()));

var app = builder.Build();

using (var scope = app.Services.CreateScope())
{
    var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
    db.Database.Migrate();
}

app.UseSwagger();
app.UseSwaggerUI(options =>
{
    options.SwaggerEndpoint("v1/swagger.json", "Audiobook Library API v1");
    options.DocumentTitle = "Audiobook Library API";
});

app.UseCors();
app.UseAuthentication();
app.UseAuthorization();

app.MapHub<LibraryHub>("/hubs/library");

app.MapAuthEndpoints();
app.MapBooksEndpoints();
app.MapGenresEndpoints();
app.MapChapterEndpoints();
app.MapProgressEndpoints();
app.MapFavoritesEndpoints();
app.MapAccountEndpoints();

app.Run();

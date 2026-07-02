namespace Server;
using Microsoft.EntityFrameworkCore;

public class AppDbContext : DbContext
{
    public DbSet<User> Users { get; set; } = default!;
    public DbSet<Book> Books { get; set; } = default!;
    public DbSet<Chapter> Chapters { get; set; } = default!;
    public DbSet<Genre> Genres { get; set; } = default!;
    public DbSet<Progress> Progress { get; set; } = null!;
    public DbSet<Favorite> Favorites { get; set; } = default!;

    public AppDbContext(DbContextOptions<AppDbContext> options) : base(options) {}
    protected override void OnModelCreating(ModelBuilder builder)
    {
        builder.Entity<Book>().HasIndex(b => b.FolderPath).IsUnique();
        builder.Entity<Book>()
            .HasMany(b => b.Chapters)
            .WithOne(c => c.Book)
            .HasForeignKey(c => c.BookId)
            .OnDelete(DeleteBehavior.Cascade);
        builder.Entity<Chapter>().HasIndex(c => c.FilePath).IsUnique();
        builder.Entity<Genre>().HasIndex(g => g.Name).IsUnique();
        builder.Entity<Progress>().HasKey(p => new { p.UserId, p.BookId });
        builder.Entity<Favorite>().HasKey(f => new { f.UserId, f.BookId });
        builder.Entity<Favorite>()
            .HasOne(f => f.Book)
            .WithMany()
            .HasForeignKey(f => f.BookId)
            .OnDelete(DeleteBehavior.Cascade);
    }
}

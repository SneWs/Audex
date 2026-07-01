namespace Server;
using Microsoft.EntityFrameworkCore;

public class AppDbContext : DbContext
{
    public DbSet<User> Users { get; set; } = default!;
    public DbSet<Book> Books { get; set; } = default!;
    public DbSet<Chapter> Chapters { get; set; } = default!;
    public DbSet<Genre> Genres { get; set; } = default!;
    public DbSet<Progress> Progress { get; set; } = null!;

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
    }
}

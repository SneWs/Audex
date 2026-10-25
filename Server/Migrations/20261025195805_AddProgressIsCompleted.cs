using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Grenis.AudioBooks.Server.Migrations
{
    /// <inheritdoc />
    public partial class AddProgressIsCompleted : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<bool>(
                name: "IsCompleted",
                table: "Progress",
                type: "boolean",
                nullable: false,
                defaultValue: false);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "IsCompleted",
                table: "Progress");
        }
    }
}

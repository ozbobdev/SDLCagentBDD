var builder = WebApplication.CreateBuilder(args);

builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

var app = builder.Build();

if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseHttpsRedirection();

var tasks = new List<TaskItem>
{
    new(1, "Create sample squad", "todo"),
    new(2, "Draft BDD scenarios", "in-progress")
};

app.MapGet("/health", () => Results.Ok(new { status = "ok" }))
   .WithName("GetHealth");

app.MapGet("/tasks", () => Results.Ok(tasks))
   .WithName("ListTasks");

app.MapPost("/tasks", (CreateTaskRequest request) =>
{
    var id = tasks.Count == 0 ? 1 : tasks.Max(t => t.Id) + 1;
    var item = new TaskItem(id, request.Title, "todo");
    tasks.Add(item);
    return Results.Created($"/tasks/{item.Id}", item);
})
.WithName("CreateTask");

app.Run();

internal sealed record TaskItem(int Id, string Title, string Status);
internal sealed record CreateTaskRequest(string Title);

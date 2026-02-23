using System.Net;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Quad.Poc.Functions.Contracts;
using Quad.Poc.Functions.Data;

namespace Quad.Poc.Functions.Functions;

public sealed class GetItemFunction
{
    private readonly SqlRepository _repository;

    public GetItemFunction(SqlRepository repository)
    {
        _repository = repository;
    }

    [Function("GetItem")]
    public async Task<HttpResponseData> Run(
        [HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "v1/items/{itemId}")] HttpRequestData request,
        string itemId,
        FunctionContext context)
    {
        string tenantId = ReadSingleHeader(request, "X-Tenant-Id") ?? "poc";
        SnapshotRecord? snapshot = await _repository.GetSnapshotAsync(
            tenantId,
            "Item",
            itemId,
            context.CancellationToken);

        if (snapshot is null)
        {
            HttpResponseData notFound = request.CreateResponse(HttpStatusCode.NotFound);
            await notFound.WriteAsJsonAsync(new ApiErrorResponse("not_found", "Item snapshot was not found."));
            return notFound;
        }

        HttpResponseData response = request.CreateResponse(HttpStatusCode.OK);
        response.Headers.Add("Content-Type", "application/json");
        response.Headers.Add("ETag", Convert.ToBase64String(snapshot.Etag));
        await response.WriteStringAsync(snapshot.SnapshotJson, context.CancellationToken);
        return response;
    }

    private static string? ReadSingleHeader(HttpRequestData request, string headerName)
    {
        if (!request.Headers.TryGetValues(headerName, out IEnumerable<string>? values))
        {
            return null;
        }

        return values.FirstOrDefault();
    }
}

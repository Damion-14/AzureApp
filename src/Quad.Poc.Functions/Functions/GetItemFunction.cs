using System.Net;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Extensions.Logging;
using Quad.Poc.Functions.Auth;
using Quad.Poc.Functions.Contracts;
using Quad.Poc.Functions.Data;

namespace Quad.Poc.Functions.Functions;

public sealed class GetItemFunction
{
    private readonly RequestAuthorizer _authorizer;
    private readonly SqlRepository _repository;
    private readonly ILogger<GetItemFunction> _logger;

    public GetItemFunction(RequestAuthorizer authorizer, SqlRepository repository, ILogger<GetItemFunction> logger)
    {
        _authorizer = authorizer;
        _repository = repository;
        _logger = logger;
    }

    [Function("GetItem")]
    public async Task<HttpResponseData> Run(
        [HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "v1/items/{itemId}")] HttpRequestData request,
        string itemId,
        FunctionContext context)
    {
        try
        {
            AuthorizationResult authorization = await _authorizer.AuthorizeAsync(request, ApiPermission.Read, context.CancellationToken);
            if (!authorization.Succeeded)
            {
                HttpResponseData deniedResponse = request.CreateResponse(authorization.FailureStatusCode ?? HttpStatusCode.Forbidden);
                await deniedResponse.WriteAsJsonAsync(authorization.Error);
                return deniedResponse;
            }

            string tenantId = authorization.Context!.TenantId;
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
            response.Headers.Add("ETag", $"\"{Convert.ToBase64String(snapshot.Etag)}\"");
            await response.WriteStringAsync(snapshot.SnapshotJson, context.CancellationToken);
            return response;
        }
        catch (Exception ex)
        {
            _logger.LogError(
                ex,
                "Unhandled error in GetItem for item {ItemId}. Request: {Method} {Url}",
                itemId,
                request.Method,
                request.Url);

            HttpResponseData response = request.CreateResponse(HttpStatusCode.InternalServerError);
            await response.WriteAsJsonAsync(new ApiErrorResponse("internal_error", "An unexpected error occurred."));
            return response;
        }
    }
}

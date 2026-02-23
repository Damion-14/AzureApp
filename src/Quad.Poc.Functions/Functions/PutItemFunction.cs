using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Quad.Poc.Functions.Contracts;
using Quad.Poc.Functions.Data;
using Quad.Poc.Functions.Messaging;

namespace Quad.Poc.Functions.Functions;

public sealed class PutItemFunction
{
    private readonly SqlRepository _repository;
    private readonly TopicPublisher _publisher;

    public PutItemFunction(SqlRepository repository, TopicPublisher publisher)
    {
        _repository = repository;
        _publisher = publisher;
    }

    [Function("PutItem")]
    public async Task<HttpResponseData> Run(
        [HttpTrigger(AuthorizationLevel.Anonymous, "put", Route = "v1/items/{itemId}")] HttpRequestData request,
        string itemId,
        FunctionContext context)
    {
        CancellationToken cancellationToken = context.CancellationToken;

        if (string.IsNullOrWhiteSpace(itemId))
        {
            return await CreateErrorResponseAsync(request, HttpStatusCode.BadRequest, "invalid_item_id", "Route parameter itemId is required.");
        }

        string? idempotencyKey = ReadSingleHeader(request, "Idempotency-Key");
        if (string.IsNullOrWhiteSpace(idempotencyKey))
        {
            return await CreateErrorResponseAsync(request, HttpStatusCode.BadRequest, "missing_idempotency_key", "Header Idempotency-Key is required.");
        }

        string tenantId = ReadSingleHeader(request, "X-Tenant-Id") ?? "poc";
        string requestBody;
        using (StreamReader reader = new(request.Body, Encoding.UTF8))
        {
            requestBody = await reader.ReadToEndAsync(cancellationToken);
        }

        if (string.IsNullOrWhiteSpace(requestBody))
        {
            return await CreateErrorResponseAsync(request, HttpStatusCode.BadRequest, "empty_body", "Request body is required.");
        }

        JsonElement payload;
        try
        {
            using JsonDocument document = JsonDocument.Parse(requestBody);
            if (document.RootElement.ValueKind != JsonValueKind.Object || !document.RootElement.EnumerateObject().Any())
            {
                return await CreateErrorResponseAsync(request, HttpStatusCode.BadRequest, "invalid_body", "Item payload must be a non-empty JSON object.");
            }

            if (document.RootElement.TryGetProperty("itemId", out JsonElement idInBody) &&
                idInBody.ValueKind == JsonValueKind.String &&
                !string.Equals(idInBody.GetString(), itemId, StringComparison.Ordinal))
            {
                return await CreateErrorResponseAsync(request, HttpStatusCode.BadRequest, "item_id_mismatch", "Body itemId does not match route itemId.");
            }

            payload = document.RootElement.Clone();
        }
        catch (JsonException)
        {
            return await CreateErrorResponseAsync(request, HttpStatusCode.BadRequest, "invalid_json", "Body must be valid JSON.");
        }

        byte[] requestHash = SHA256.HashData(Encoding.UTF8.GetBytes(requestBody));
        OperationCreateResult createResult = await _repository.CreateOperationAsync(
            tenantId,
            idempotencyKey,
            requestHash,
            "Item",
            itemId,
            cancellationToken);

        if (createResult.Outcome == OperationCreateOutcome.ConflictDifferentHash)
        {
            return await CreateErrorResponseAsync(
                request,
                HttpStatusCode.Conflict,
                "idempotency_conflict",
                "Idempotency key was already used with a different request payload.");
        }

        if (createResult.Outcome == OperationCreateOutcome.Created)
        {
            CommandEnvelope command = new()
            {
                CommandType = "Item.Upsert",
                CommandId = Guid.NewGuid(),
                OperationId = createResult.OperationId,
                TenantId = tenantId,
                IdempotencyKey = idempotencyKey,
                ResourceId = itemId,
                Payload = payload
            };

            try
            {
                await _publisher.PublishCommandAsync(command, cancellationToken);
            }
            catch (Exception ex)
            {
                await _repository.MarkOperationFailedAsync(
                    createResult.OperationId,
                    "publish_failed",
                    ex.Message,
                    cancellationToken);

                return await CreateErrorResponseAsync(
                    request,
                    HttpStatusCode.InternalServerError,
                    "publish_failed",
                    "Failed to enqueue command message.");
            }
        }

        string baseUrl = $"{request.Url.Scheme}://{request.Url.Authority}";
        AcceptedOperationResponse responseModel = new(
            createResult.OperationId,
            $"{baseUrl}/v1/operations/{createResult.OperationId}",
            $"{baseUrl}/v1/items/{itemId}");

        HttpResponseData response = request.CreateResponse(HttpStatusCode.Accepted);
        await response.WriteAsJsonAsync(responseModel, cancellationToken: cancellationToken);
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

    private static async Task<HttpResponseData> CreateErrorResponseAsync(
        HttpRequestData request,
        HttpStatusCode statusCode,
        string code,
        string message)
    {
        HttpResponseData response = request.CreateResponse(statusCode);
        await response.WriteAsJsonAsync(new ApiErrorResponse(code, message));
        return response;
    }
}

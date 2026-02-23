using System.Net;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Quad.Poc.Functions.Contracts;
using Quad.Poc.Functions.Data;

namespace Quad.Poc.Functions.Functions;

public sealed class GetOperationFunction
{
    private readonly SqlRepository _repository;

    public GetOperationFunction(SqlRepository repository)
    {
        _repository = repository;
    }

    [Function("GetOperation")]
    public async Task<HttpResponseData> Run(
        [HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "v1/operations/{operationId}")] HttpRequestData request,
        string operationId,
        FunctionContext context)
    {
        if (!Guid.TryParse(operationId, out Guid parsedOperationId))
        {
            HttpResponseData invalidResponse = request.CreateResponse(HttpStatusCode.BadRequest);
            await invalidResponse.WriteAsJsonAsync(new ApiErrorResponse("invalid_operation_id", "operationId must be a GUID."));
            return invalidResponse;
        }

        OperationRecord? operation = await _repository.GetOperationAsync(parsedOperationId, context.CancellationToken);
        if (operation is null)
        {
            HttpResponseData notFound = request.CreateResponse(HttpStatusCode.NotFound);
            await notFound.WriteAsJsonAsync(new ApiErrorResponse("not_found", "Operation was not found."));
            return notFound;
        }

        string baseUrl = $"{request.Url.Scheme}://{request.Url.Authority}";
        OperationStatusResponse responseModel = new(
            operation.OperationId,
            operation.TenantId,
            operation.Status,
            operation.ErrorCode,
            operation.ErrorMessage,
            operation.ResourceType,
            operation.ResourceId,
            operation.CreatedAt,
            operation.UpdatedAt,
            $"{baseUrl}/v1/items/{operation.ResourceId}");

        HttpResponseData response = request.CreateResponse(HttpStatusCode.OK);
        await response.WriteAsJsonAsync(responseModel, cancellationToken: context.CancellationToken);
        return response;
    }
}

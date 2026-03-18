using Microsoft.Azure.Functions.Worker.Http;
using Quad.Poc.Functions.Contracts;
using Quad.Poc.Functions.Data;
using System.Net;
using System.Security.Cryptography;
using System.Text;

namespace Quad.Poc.Functions.Auth;

public enum ApiPermission
{
    Read,
    Write
}

public sealed record RequestAuthorizationContext(
    string ClientId,
    string TenantId,
    string? DisplayName,
    IReadOnlyCollection<string> Roles);

public sealed record AuthorizationResult(
    RequestAuthorizationContext? Context,
    HttpStatusCode? FailureStatusCode,
    ApiErrorResponse? Error)
{
    public bool Succeeded => Context is not null;

    public static AuthorizationResult Success(RequestAuthorizationContext context)
    {
        return new(context, null, null);
    }

    public static AuthorizationResult Failure(HttpStatusCode statusCode, string code, string message)
    {
        return new(null, statusCode, new ApiErrorResponse(code, message));
    }
}

public sealed class RequestAuthorizer
{
    private const string ApiKeyHeader = "X-Api-Key";
    private readonly SqlRepository _repository;

    public RequestAuthorizer(SqlRepository repository)
    {
        _repository = repository;
    }

    public async Task<AuthorizationResult> AuthorizeAsync(HttpRequestData request, ApiPermission permission, CancellationToken cancellationToken)
    {
        string? apiKey = ReadSingleHeader(request, ApiKeyHeader);
        if (string.IsNullOrWhiteSpace(apiKey))
        {
            return AuthorizationResult.Failure(
                HttpStatusCode.Unauthorized,
                "api_key_required",
                $"Header {ApiKeyHeader} is required.");
        }

        byte[] apiKeyHash = SHA256.HashData(Encoding.UTF8.GetBytes(apiKey));
        AuthorizedApiKeyRecord? client = await _repository.GetAuthorizedClientByApiKeyHashAsync(
            apiKeyHash,
            cancellationToken);

        if (client is null)
        {
            return AuthorizationResult.Failure(HttpStatusCode.Unauthorized, "invalid_api_key", "API key is invalid.");
        }

        if (!client.ClientIsActive)
        {
            return AuthorizationResult.Failure(HttpStatusCode.Forbidden, "client_disabled", "Caller is disabled.");
        }

        if (!client.KeyIsActive || client.RevokedAt is not null)
        {
            return AuthorizationResult.Failure(HttpStatusCode.Forbidden, "api_key_inactive", "API key is inactive.");
        }

        if (client.ExpiresAt is not null && client.ExpiresAt <= DateTime.UtcNow)
        {
            return AuthorizationResult.Failure(HttpStatusCode.Forbidden, "api_key_expired", "API key has expired.");
        }

        return AuthorizationResult.Success(new RequestAuthorizationContext(
            client.ClientId.ToString(),
            client.TenantId,
            client.Name,
            Array.Empty<string>()));
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

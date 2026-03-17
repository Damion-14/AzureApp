using System.Net;
using System.Text.Json;
using Microsoft.Azure.Functions.Worker.Http;
using Quad.Poc.Functions.Contracts;

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

    public static AuthorizationResult Success(RequestAuthorizationContext context) => new(context, null, null);

    public static AuthorizationResult Failure(HttpStatusCode statusCode, string code, string message)
        => new(null, statusCode, new ApiErrorResponse(code, message));
}

internal sealed record ClientPrincipalClaim(string Type, string Value);

internal sealed record ClientPrincipalPayload(string? AuthenticationType, string? RoleType, IReadOnlyList<ClientPrincipalClaim> Claims);

public sealed class RequestAuthorizer
{
    private static readonly string[] ClientIdClaimTypes =
    [
        "appid",
        "azp",
        "client_id",
        "http://schemas.microsoft.com/identity/claims/clientid"
    ];

    private static readonly string[] DisplayNameClaimTypes =
    [
        "name",
        "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name"
    ];

    private static readonly string[] DefaultRoleClaimTypes =
    [
        "roles",
        "role",
        "http://schemas.microsoft.com/ws/2008/06/identity/claims/role"
    ];

    private readonly AuthOptions _options;

    public RequestAuthorizer(AuthOptions options)
    {
        _options = options;
    }

    public AuthorizationResult Authorize(HttpRequestData request, ApiPermission permission)
    {
        if (!_options.Enabled)
        {
            string tenantId = ReadSingleHeader(request, "X-Tenant-Id") ?? _options.DefaultTenantId;
            return AuthorizationResult.Success(new RequestAuthorizationContext(
                "local-development",
                tenantId,
                "Local development",
                Array.Empty<string>()));
        }

        string? encodedClientPrincipal = ReadSingleHeader(request, "X-MS-CLIENT-PRINCIPAL");
        if (string.IsNullOrWhiteSpace(encodedClientPrincipal))
        {
            return AuthorizationResult.Failure(
                HttpStatusCode.Unauthorized,
                "authentication_required",
                "Authentication is required.");
        }

        ClientPrincipalPayload? principal;
        try
        {
            principal = DecodeClientPrincipal(encodedClientPrincipal);
        }
        catch (Exception)
        {
            return AuthorizationResult.Failure(
                HttpStatusCode.Unauthorized,
                "invalid_principal",
                "Authenticated principal header is invalid.");
        }

        if (principal is null || string.IsNullOrWhiteSpace(principal.AuthenticationType))
        {
            return AuthorizationResult.Failure(
                HttpStatusCode.Unauthorized,
                "invalid_principal",
                "Authenticated principal is missing.");
        }

        string? clientId = GetFirstClaimValue(principal.Claims, ClientIdClaimTypes);
        if (string.IsNullOrWhiteSpace(clientId))
        {
            return AuthorizationResult.Failure(
                HttpStatusCode.Forbidden,
                "client_not_identified",
                "Authenticated client application could not be identified.");
        }

        if (!_options.AuthorizedClients.TryGetValue(clientId, out AuthorizedClient? authorizedClient))
        {
            return AuthorizationResult.Failure(
                HttpStatusCode.Forbidden,
                "client_not_allowed",
                "Authenticated client application is not allowed.");
        }

        HashSet<string> roles = GetRoles(principal);
        string requiredRole = permission == ApiPermission.Write ? _options.WriteRole : _options.ReadRole;

        if (!string.IsNullOrWhiteSpace(requiredRole) && !roles.Contains(requiredRole))
        {
            return AuthorizationResult.Failure(
                HttpStatusCode.Forbidden,
                "insufficient_role",
                $"Authenticated client application is missing required role '{requiredRole}'.");
        }

        return AuthorizationResult.Success(new RequestAuthorizationContext(
            clientId,
            authorizedClient.TenantId,
            GetFirstClaimValue(principal.Claims, DisplayNameClaimTypes) ?? authorizedClient.Name,
            roles));
    }

    private static ClientPrincipalPayload DecodeClientPrincipal(string encodedClientPrincipal)
    {
        byte[] rawBytes = Convert.FromBase64String(encodedClientPrincipal);
        using JsonDocument document = JsonDocument.Parse(rawBytes);
        JsonElement root = document.RootElement;

        List<ClientPrincipalClaim> claims = [];
        if (root.TryGetProperty("claims", out JsonElement claimsElement) && claimsElement.ValueKind == JsonValueKind.Array)
        {
            foreach (JsonElement claim in claimsElement.EnumerateArray())
            {
                string? type = claim.TryGetProperty("typ", out JsonElement typeElement) ? typeElement.GetString() : null;
                string? value = claim.TryGetProperty("val", out JsonElement valueElement) ? valueElement.GetString() : null;

                if (!string.IsNullOrWhiteSpace(type) && value is not null)
                {
                    claims.Add(new ClientPrincipalClaim(type, value));
                }
            }
        }

        string? authenticationType = root.TryGetProperty("auth_typ", out JsonElement authTypeElement)
            ? authTypeElement.GetString()
            : null;
        string? roleType = root.TryGetProperty("role_typ", out JsonElement roleTypeElement)
            ? roleTypeElement.GetString()
            : null;

        return new ClientPrincipalPayload(authenticationType, roleType, claims);
    }

    private static HashSet<string> GetRoles(ClientPrincipalPayload principal)
    {
        HashSet<string> roleClaimTypes = new(StringComparer.OrdinalIgnoreCase);
        foreach (string claimType in DefaultRoleClaimTypes)
        {
            roleClaimTypes.Add(claimType);
        }

        if (!string.IsNullOrWhiteSpace(principal.RoleType))
        {
            roleClaimTypes.Add(principal.RoleType);
        }

        HashSet<string> roles = new(StringComparer.OrdinalIgnoreCase);
        foreach (ClientPrincipalClaim claim in principal.Claims)
        {
            if (roleClaimTypes.Contains(claim.Type) && !string.IsNullOrWhiteSpace(claim.Value))
            {
                roles.Add(claim.Value);
            }
        }

        return roles;
    }

    private static string? GetFirstClaimValue(IEnumerable<ClientPrincipalClaim> claims, IEnumerable<string> claimTypes)
    {
        HashSet<string> normalizedClaimTypes = new(claimTypes, StringComparer.OrdinalIgnoreCase);
        return claims.FirstOrDefault(claim => normalizedClaimTypes.Contains(claim.Type))?.Value;
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

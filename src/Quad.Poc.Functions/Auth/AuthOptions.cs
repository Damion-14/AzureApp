using System.Text.Json;
using Microsoft.Extensions.Configuration;

namespace Quad.Poc.Functions.Auth;

public sealed record AuthorizedClient(string ClientId, string TenantId, string? Name);

public sealed class AuthOptions
{
    public bool Enabled { get; init; }

    public string ReadRole { get; init; } = "items.read";

    public string WriteRole { get; init; } = "items.write";

    public string DefaultTenantId { get; init; } = "poc";

    public IReadOnlyDictionary<string, AuthorizedClient> AuthorizedClients { get; init; }
        = new Dictionary<string, AuthorizedClient>(StringComparer.OrdinalIgnoreCase);

    public static AuthOptions FromConfiguration(IConfiguration configuration)
    {
        string authorizedClientsJson = configuration["Auth:AuthorizedClientsJson"] ?? "[]";
        List<AuthorizedClient>? authorizedClients;
        try
        {
            authorizedClients = JsonSerializer.Deserialize<List<AuthorizedClient>>(
                authorizedClientsJson,
                new JsonSerializerOptions(JsonSerializerDefaults.Web));
        }
        catch (JsonException ex)
        {
            throw new InvalidOperationException("Auth:AuthorizedClientsJson must be valid JSON.", ex);
        }

        Dictionary<string, AuthorizedClient> clientsById = new(StringComparer.OrdinalIgnoreCase);
        foreach (AuthorizedClient client in authorizedClients ?? [])
        {
            if (string.IsNullOrWhiteSpace(client.ClientId) || string.IsNullOrWhiteSpace(client.TenantId))
            {
                continue;
            }

            clientsById[client.ClientId] = client with
            {
                ClientId = client.ClientId.Trim(),
                TenantId = client.TenantId.Trim(),
                Name = string.IsNullOrWhiteSpace(client.Name) ? null : client.Name.Trim()
            };
        }

        return new AuthOptions
        {
            Enabled = bool.TryParse(configuration["Auth:Enabled"], out bool enabled) && enabled,
            ReadRole = configuration["Auth:ReadRole"] ?? "items.read",
            WriteRole = configuration["Auth:WriteRole"] ?? "items.write",
            DefaultTenantId = configuration["Auth:DefaultTenantId"] ?? "poc",
            AuthorizedClients = clientsById
        };
    }
}

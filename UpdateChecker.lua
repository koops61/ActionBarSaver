local currentVersion = "v3.0"  -- version actuelle de ton addon

local function checkForUpdate()
    local url = "https://api.github.com/repos/koops61/ActionBarSaver/releases/latest"

    C_Timer.After(5, function()
        -- Créer une requête HTTP pour vérifier la dernière version sur GitHub
        local request = {
            url = url,
            method = "GET",
            success = function(response)
                local data = C_LFGList.JSONDecode(response)
                if data and data.tag_name then
                    if data.tag_name ~= currentVersion then
                        print("|cFFFF0000Nouvelle version disponible : " .. data.tag_name .. ". Téléchargez-la depuis GitHub.|r")
                    else
                        print("|cFF00FF00Votre addon est à jour.|r")
                    end
                else
                    print("|cFFFF0000Erreur lors de la vérification de la version.|r")
                end
            end,
            failed = function(error)
                print("|cFFFF0000Impossible de vérifier la mise à jour : " .. error .. "|r")
            end
        }

        -- Envoyer la requête
        C_LFGList.SendHTTPRequest(request)
    end)
end

-- Appel de la fonction pour vérifier les mises à jour au lancement
checkForUpdate()

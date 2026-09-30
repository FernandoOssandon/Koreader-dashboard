-- Quita el token de cualquier texto antes de que llegue a un mensaje o al log.
return function(msg, token)
    msg = tostring(msg)
    if token and token ~= "" then
        local i, j = msg:find(token, 1, true)
        while i do
            msg = msg:sub(1, i - 1) .. "***" .. msg:sub(j + 1)
            i, j = msg:find(token, i + 3, true)
        end
    end
    return msg
end

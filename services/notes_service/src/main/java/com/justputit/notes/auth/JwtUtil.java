package com.justputit.notes.auth;

import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.security.Keys;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.Date;
import javax.crypto.SecretKey;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

@Component
public class JwtUtil {

    @Value("${jwt.secret:defaultSecretKeyThatIsAtLeast32CharactersLong!}")
    private String secret;

    public String generateToken(String email) {
        SecretKey key = Keys.hmacShaKeyFor(secret.getBytes());
        Instant now = Instant.now();
        Instant expiry = now.plus(24, ChronoUnit.HOURS);

        return Jwts.builder()
                .subject(email)
                .issuedAt(Date.from(now))
                .expiration(Date.from(expiry))
                .signWith(key, Jwts.SIG.HS256)
                .compact();
    }
}

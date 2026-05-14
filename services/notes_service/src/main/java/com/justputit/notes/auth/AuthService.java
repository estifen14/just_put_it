package com.justputit.notes.auth;

import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class AuthService {

    private final UserRepository userRepository;
    private final JwtUtil jwtUtil;
    private final PasswordEncoder passwordEncoder;

    public AuthService(UserRepository userRepository, JwtUtil jwtUtil, PasswordEncoder passwordEncoder) {
        this.userRepository = userRepository;
        this.jwtUtil = jwtUtil;
        this.passwordEncoder = passwordEncoder;

    }

    @Transactional
    public String registerUser(RegisterRequest request) {
        String email = request.getEmail().toLowerCase();
        
        if (userRepository.existsByEmailIgnoreCase(email)) {
            throw new DuplicateEmailException("Email is already in use.");
        }

        User user = new User();
        user.setEmail(email);
        user.setPasswordHash(passwordEncoder.encode(request.getPassword()));
        
        userRepository.save(user);

        return jwtUtil.generateToken(user.getEmail());
    }
}

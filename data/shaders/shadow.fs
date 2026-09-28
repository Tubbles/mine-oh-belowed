#version 330

// Shadow map depth pass (work item 0072): only the depth is kept, the
// framebuffer has no colour attachment.

out vec4 finalColor;

void main()
{
    finalColor = vec4(1.0);
}

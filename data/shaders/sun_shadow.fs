#version 330

// The sun's shadow map (work item 0328, render_sun_shadows.odin): only
// the depth is kept, the framebuffer has no colour attachment.

out vec4 finalColor;

void main()
{
    finalColor = vec4(1.0);
}

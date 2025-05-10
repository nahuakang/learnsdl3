struct Input {
	float4 color : TEXCOORD0;
	float2 uv : TEXCOORD1;
};

Texture2D<float4> tex : register(t0, space2);
SamplerState smp : register(s0, space2);

float4 main(Input input) : SV_Target0 {
	float4 color = tex.Sample(smp, input.uv);
	
	float4 finalColor = color * input.color;
	return finalColor;
}

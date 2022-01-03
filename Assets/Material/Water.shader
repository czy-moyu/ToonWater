Shader "Unlit/sea2"
{
	Properties
	{
		_FoamTex("FoamTex",2D) = "White"{}
		_WaveSpeed("WaveSpeed",Range(0.1, 2)) = 1
		_Edge("Edge", Range(0.1, 2)) = 1
		_FoamScaleX("FoamScaleX", Range(0.001, 0.05)) = 1
		_FoamScaleZ("FoamScaleZ", Range(0.001, 0.2)) = 1
		_FoamDensity("FoamDensity", Range(0.1, 1)) = 1
	}
	SubShader
	{
		Tags { 
				"RenderType"="Opaque"
				"Queue"="Transparent"
			 }
		LOD 100
		Blend SrcAlpha OneMinusSrcAlpha 

		Pass
		{
			HLSLPROGRAM
			#pragma vertex vert
			#pragma fragment frag
			// make fog work
			#pragma multi_compile_fog
			// #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
			// #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
			#include "UnityCG.cginc"

			struct appdata
			{
				float4 vertex : POSITION;
				float3 normal : NORMAL;
				// float2 uv : TEXCOORD;
			};

			struct v2f
			{
				UNITY_FOG_COORDS(4)
				float4 vertex : SV_POSITION;
				// float2 uv : TEXCOORD0;
				float3 worldNormal : TEXCOORD1;
				float4 projPos : TEXCOORD2;
				float3 worldPos : TEXCOORD3;
			};

			sampler2D _FoamTex;
			CBUFFER_START(UnityPerMaterial)
			float _WaveSpeed;
			float _Edge;
			float _FoamScaleX;
			float _FoamScaleZ;
			float _FoamDensity;
			CBUFFER_END

			v2f vert (appdata v)
			{
				v2f o;
				o.vertex = UnityObjectToClipPos(v.vertex);
				UNITY_TRANSFER_FOG(o,o.vertex);
				
				o.projPos = ComputeScreenPos(o.vertex);
				o.worldPos = mul(unity_ObjectToWorld, v.vertex).xyz;
				o.worldNormal = UnityObjectToWorldNormal(v.normal);
				// o.uv = TRANSFORM_TEX(v.uv, _FoamTex);
				COMPUTE_EYEDEPTH(o.projPos.z);
				return o;
			}
			
			fixed4 cosine_gradient(float x,  fixed4 phase, fixed4 amp, fixed4 freq, fixed4 offset){
				const float TAU = 2. * 3.14159265;
  				phase *= TAU;
  				x *= TAU;

  				return fixed4(
    				offset.r + amp.r * 0.5 * cos(x * freq.r + phase.r) + 0.5,
    				offset.g + amp.g * 0.5 * cos(x * freq.g + phase.g) + 0.5,
    				offset.b + amp.b * 0.5 * cos(x * freq.b + phase.b) + 0.5,
    				offset.a + amp.a * 0.5 * cos(x * freq.a + phase.a) + 0.5
  				);
			}
			
			float2 rand(float2 st, int seed)
			{
				float2 s = float2(dot(st, float2(127.1, 311.7)) + seed, dot(st, float2(269.5, 183.3)) + seed);
				return -1 + 2 * frac(sin(s) * 43758.5453123);
			}
			
			float noise(float2 st, int seed)
			{
				st.y -= _Time[1];

				float2 p = floor(st);
				float2 f = frac(st);
 
				float w00 = dot(rand(p, seed), f);
				float w10 = dot(rand(p + float2(1, 0), seed), f - float2(1, 0));
				float w01 = dot(rand(p + float2(0, 1), seed), f - float2(0, 1));
				float w11 = dot(rand(p + float2(1, 1), seed), f - float2(1, 1));
				
				float2 u = f * f * (3 - 2 * f);
 
				return lerp(lerp(w00, w10, u.x), lerp(w01, w11, u.x), u.y);
			}
			
			float3 swell(float3 normal, float anisotropy, float height){
				height *= anisotropy ;
				normal = normalize(
					cross ( 
						float3(0,ddy(height),1),
						float3(1,ddx(height),0)
					)
				);
				return normal;
			}

			UNITY_DECLARE_DEPTH_TEXTURE(_CameraDepthTexture);	
			fixed4 frag (v2f i) : SV_Target
			{
				// sample the texture
				fixed4 col;
				float3 positionWS = i.worldPos;

				// view空间的深度
    			float sceneZ = LinearEyeDepth(SAMPLE_DEPTH_TEXTURE_PROJ(
    				_CameraDepthTexture, UNITY_PROJ_COORD(i.projPos)));
				float partZ = i.projPos.z;
				float diffZ = saturate( (sceneZ - partZ) * rcp(10.0f));

				// todo 直接采样渐变贴图
				// 相位
				const fixed4 phases = fixed4(0.28, 0.50, 0.07, 0.);
				// 振幅
				const fixed4 amplitudes = fixed4(4.02, 0.34, 0.65, 0.);
				// 频率
				const fixed4 frequencies = fixed4(0.00, 0.48, 0.08, 0.);
				// y offset
				const fixed4 offsets = fixed4(0.00, 0.16, 0.00, 0.);

				// 颜色渐变
				fixed4 cos_grad = cosine_gradient(
					1 - diffZ, phases, amplitudes, frequencies, offsets);
  				cos_grad = saturate(cos_grad);
  				col.rgb = cos_grad.rgb;
					
				// 波にゆらぎを与える
				half3 worldViewDir = normalize(_WorldSpaceCameraPos - i.worldPos);

				// 离相机越远，起伏程度就越小
				float3 v = i.worldPos - _WorldSpaceCameraPos;
				float anisotropy = 1 * rcp(ddy(length(v.xz))) * rcp(5);
				anisotropy = saturate(anisotropy);
				// 根据柏林噪声计算法线
				float height = noise(i.worldPos.xz * 0.1,0);
				float3 swelledNormal = swell(i.worldNormal, anisotropy, height);

				// 反射天空盒
                half3 reflDir = reflect(-worldViewDir, swelledNormal);
				half4 skyData = UNITY_SAMPLE_TEXCUBE_LOD(unity_SpecCube0, reflDir, 0);
				half3 skyColor = DecodeHDR(skyData, unity_SpecCube0_HDR);
				/* speclar
				float spe = pow( saturate(dot( reflDir, normalize(_lightPos.xyz))),100);
				float3 lightColor = float3(1,1,1);
				reflectionColor += 0.4 * half4((spe * lightColor).xxxx);
				*/
				
				
				// 菲涅尔反射
				float f0 = 0.02;
    			float vReflect = f0 + (1-f0) * pow((1 - dot(worldViewDir,swelledNormal)),5);
				vReflect = saturate(vReflect * 2.0);
				col.rgb = lerp(col , skyColor , vReflect);

				//岸边浪花
				positionWS.xz *= float2(_FoamScaleX, _FoamScaleZ);
                positionWS.z -= _Time.y * _WaveSpeed;
                half4 foamTexCol = tex2D(_FoamTex, positionWS.xz);
				// 高度大于0.8的泡沫被隐藏
                half foamCol = saturate((0.8 - height) * (foamTexCol.r + foamTexCol.g));
				// foamCol *= diffZ * 5.0;
				foamCol = step(_FoamDensity, foamCol);
				// foamCol *= saturate(_Edge - diffZ);
				foamCol *= step(_Edge, 2.0 - diffZ);
				// foamCol *= 3.0;
				// col.xyz += foamCol;
                col.rgb = lerp(col.rgb, 1.0, foamCol);
				// return half4(col.xyz,0.5);
			 
				//地平线处边缘光，使海水更通透
				float rimLight = ddy(length(v.xz)) * rcp(100.0);
				col.rgb += rimLight;
				
				float alpha = saturate(diffZ);
  				col.a = alpha + foamCol * diffZ * 30.0;
  				// col.a = 0.51;
			 
				return col;
				// return half4(rimLight,rimLight,rimLight,1.0);
			}
			ENDHLSL
		}
	}
}
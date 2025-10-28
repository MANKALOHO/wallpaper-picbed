# api/python_demo.py - Python调用二次元壁纸API示例
import requests

def get_random_wallpaper():
    """获取随机二次元壁纸（JSON格式）"""
    api_url = "https://你的域名/?type=random&format=json"
    try:
        response = requests.get(api_url)
        response.raise_for_status()  # 抛出自定义错误
        data = response.json()
        if data["code"] == 200:
            print("获取成功！")
            print(f"壁纸名称：{data['data']['壁纸名称']}")
            print(f"壁纸直链：{data['data']['壁纸直链']}")
            return data["data"]["壁纸直链"]
        else:
            print(f"接口错误：{data['message']}")
    except Exception as e:
        print(f"请求失败：{str(e)}")

def save_wallpaper_to_local():
    """获取壁纸并保存到本地"""
    wallpaper_url = get_random_wallpaper()
    if wallpaper_url:
        response = requests.get(wallpaper_url)
        with open("anime_wallpaper.jpg", "wb") as f:
            f.write(response.content)
        print("壁纸已保存为 anime_wallpaper.jpg")

# 调用示例
# save_wallpaper_to_local()
